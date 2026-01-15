#!/usr/bin/env python3
"""
AKS Add-on Inventory
====================
Inventories enabled add-ons across AKS clusters to understand feature adoption.

Usage:
    python aks_addon_inventory.py [--config config.json] [--subscription sub_id]
"""

import argparse
from azure.mgmt.containerservice import ContainerServiceClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

# Known add-on keys and their friendly names
ADDON_MAP = {
    'azurepolicy': 'Azure Policy',
    'azureKeyvaultSecretsProvider': 'Key Vault CSI',
    'gitops': 'GitOps (Flux)',
    'omsagent': 'Container Insights',
    'ingressApplicationGateway': 'AGIC',
    'httpApplicationRouting': 'HTTP Routing (Deprecated)',
    'aciConnectorLinux': 'Virtual Nodes',
    'azureDefender': 'Defender',
    'openServiceMesh': 'Open Service Mesh',
    'kubeDashboard': 'Kube Dashboard (Deprecated)',
}

def enabled_icon(enabled):
    return f"{Fore.GREEN}✓{Style.RESET_ALL}" if enabled else f"{Fore.RED}✗{Style.RESET_ALL}"

def get_addon_status(cluster):
    """Returns a dict of addon statuses."""
    addons = cluster.addon_profiles or {}
    result = {}
    
    for key, friendly in ADDON_MAP.items():
        addon = addons.get(key, {})
        enabled = addon.get('enabled', False) if addon else False
        result[friendly] = enabled
    
    return result

def main():
    parser = argparse.ArgumentParser(description="AKS Add-on Inventory")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    # Build headers dynamically
    headers = ["Cluster"] + list(ADDON_MAP.values())
    data = []

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

                addon_status = get_addon_status(cluster)
                row = [cluster.name] + [enabled_icon(addon_status.get(name, False)) for name in ADDON_MAP.values()]
                data.append(row)

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
