#!/usr/bin/env python3
"""
AKS Key Vault Integration
=========================
Checks for Key Vault CSI driver add-on and rotation settings.

Usage:
    python aks_keyvault_integration.py [--config config.json] [--subscription sub_id]
"""

import argparse
from azure.mgmt.containerservice import ContainerServiceClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def check_keyvault_addon(cluster):
    """Checks Key Vault CSI driver add-on status."""
    addons = cluster.addon_profiles or {}
    
    kv_addon = addons.get('azureKeyvaultSecretsProvider', {})
    if not kv_addon:
        return False, False
    
    enabled = kv_addon.get('enabled', False)
    
    # Check for secret rotation
    config = kv_addon.get('config', {})
    rotation_enabled = False
    if config:
        rotation_enabled = config.get('enableSecretRotation', 'false').lower() == 'true'
    
    return enabled, rotation_enabled

def main():
    parser = argparse.ArgumentParser(description="AKS Key Vault Integration")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["Cluster", "KV CSI Driver", "Secret Rotation", "Recommendation"]

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

                kv_enabled, rotation = check_keyvault_addon(cluster)
                
                kv_status = f"{Fore.GREEN}Enabled{Style.RESET_ALL}" if kv_enabled else f"{Fore.YELLOW}Disabled{Style.RESET_ALL}"
                rotation_status = f"{Fore.GREEN}Enabled{Style.RESET_ALL}" if rotation else f"{Fore.YELLOW}Disabled{Style.RESET_ALL}"
                
                # Recommendations
                recs = []
                if not kv_enabled:
                    recs.append("Enable Key Vault CSI")
                elif not rotation:
                    recs.append("Enable secret rotation")
                
                rec_str = "; ".join(recs) if recs else f"{Fore.GREEN}OK{Style.RESET_ALL}"
                
                data.append([cluster.name, kv_status, rotation_status, rec_str])

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
