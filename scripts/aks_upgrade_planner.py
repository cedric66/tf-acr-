#!/usr/bin/env python3
"""
AKS Upgrade Planner
===================
Compares AKS cluster versions against available upgrades to help plan maintenance windows.

Usage:
    python aks_upgrade_planner.py [--config config.json] [--subscription sub_id]
"""

import argparse
from azure.mgmt.containerservice import ContainerServiceClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def get_upgrade_info(aks_client, rg_name, cluster_name, current_version):
    """Gets available upgrade paths for a cluster."""
    try:
        upgrade_profile = aks_client.managed_clusters.get_upgrade_profile(rg_name, cluster_name)
        
        if not upgrade_profile or not upgrade_profile.control_plane_profile:
            return [], False
        
        cp = upgrade_profile.control_plane_profile
        available_upgrades = []
        
        if cp.upgrades:
            for upgrade in cp.upgrades:
                available_upgrades.append(upgrade.kubernetes_version)
        
        # Check if current version is being deprecated
        is_preview = False
        # Note: The API doesn't directly tell us if deprecated, but we can infer from upgrade availability
        
        return available_upgrades, is_preview
        
    except Exception as e:
        utils.handle_azure_error(e, "Upgrade Profile", f"{rg_name}/{cluster_name}")
        return [], False

def version_status(version, upgrades):
    """Determines the status of the current version."""
    if not version:
        return f"{Fore.RED}Unknown{Style.RESET_ALL}"
    
    major, minor, *patch = version.split('.')
    minor_int = int(minor) if minor.isdigit() else 0
    
    # Rough heuristic: If there are 3+ minor versions ahead, consider it outdated
    if upgrades:
        latest = upgrades[-1]  # Usually sorted ascending
        latest_major, latest_minor, *_ = latest.split('.')
        latest_minor_int = int(latest_minor) if latest_minor.isdigit() else 0
        
        diff = latest_minor_int - minor_int
        if diff >= 3:
            return f"{Fore.RED}Outdated ({diff} behind){Style.RESET_ALL}"
        elif diff >= 1:
            return f"{Fore.YELLOW}Upgradable (+{diff}){Style.RESET_ALL}"
    
    return f"{Fore.GREEN}Current{Style.RESET_ALL}"

def main():
    parser = argparse.ArgumentParser(description="AKS Upgrade Planner")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["Cluster", "Current Version", "Status", "Available Upgrades"]

    for sub in subs:
        try:
            aks_client = ContainerServiceClient(cred, sub.subscription_id)
            clusters = list(aks_client.managed_clusters.list())
            
            for cluster in clusters:
                rg_name = cluster.id.split('/')[4]
                if not utils.should_process_resource_group(rg_name, sub.subscription_id, config):
                    continue
                if not utils.should_process_cluster(cluster.name, sub.subscription_id, config):
                    continue

                current_ver = cluster.kubernetes_version
                upgrades, _ = get_upgrade_info(aks_client, rg_name, cluster.name, current_ver)
                
                status = version_status(current_ver, upgrades)
                upgrade_str = ", ".join(upgrades[-3:]) if upgrades else "None available"
                if len(upgrades) > 3:
                    upgrade_str = f"... {upgrade_str}"
                
                data.append([
                    cluster.name,
                    current_ver,
                    status,
                    upgrade_str
                ])

        except Exception as e:
            if not utils.handle_azure_error(e, "AKS Clusters", f"Subscription: {sub.subscription_id}"):
                break
            continue

    if not data:
        print(f"{Fore.YELLOW}No clusters found.{Style.RESET_ALL}")
    else:
        print(tabulate(data, headers=headers, tablefmt="grid"))

if __name__ == "__main__":
    main()
