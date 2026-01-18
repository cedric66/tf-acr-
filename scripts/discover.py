#!/usr/bin/env python3
"""
AKS/ACR Discovery Script
========================
Scans all accessible subscriptions and outputs CSV inventories.
These CSVs can be filtered and used as input for other audit scripts.

Usage:
    python discover.py [--output ./inventory/]
"""

import argparse
import os
import csv
from datetime import datetime
from azure.mgmt.containerservice import ContainerServiceClient
from azure.mgmt.containerregistry import ContainerRegistryManagementClient
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def discover_clusters(cred, subs, output_dir):
    """Discovers all AKS clusters and writes to CSV."""
    clusters = []
    
    print(f"{Fore.CYAN}Discovering AKS clusters...{Style.RESET_ALL}")
    
    for sub in subs:
        try:
            aks_client = ContainerServiceClient(cred, sub.subscription_id)
            cluster_list = list(aks_client.managed_clusters.list())
            
            for c in cluster_list:
                rg = c.id.split('/')[4]
                clusters.append({
                    'subscription_id': sub.subscription_id,
                    'resource_group': rg,
                    'cluster_name': c.name,
                    'location': c.location,
                    'kubernetes_version': c.kubernetes_version,
                    'power_state': c.power_state.code if c.power_state else 'Unknown',
                    'node_count': sum(p.count for p in c.agent_pool_profiles) if c.agent_pool_profiles else 0,
                    'private_cluster': c.api_server_access_profile.enable_private_cluster if c.api_server_access_profile else False
                })
                
        except Exception as e:
            utils.handle_azure_error(e, "AKS Discovery", f"Sub: {sub.subscription_id}")
            continue
    
    if clusters:
        filepath = os.path.join(output_dir, 'clusters.csv')
        with open(filepath, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=clusters[0].keys())
            writer.writeheader()
            writer.writerows(clusters)
        print(f"{Fore.GREEN}✓ Found {len(clusters)} clusters → {filepath}{Style.RESET_ALL}")
    else:
        print(f"{Fore.YELLOW}No clusters found.{Style.RESET_ALL}")
    
    return clusters

def discover_acrs(cred, subs, output_dir):
    """Discovers all ACRs and writes to CSV."""
    acrs = []
    
    print(f"{Fore.CYAN}Discovering Azure Container Registries...{Style.RESET_ALL}")
    
    for sub in subs:
        try:
            acr_client = ContainerRegistryManagementClient(cred, sub.subscription_id)
            registry_list = list(acr_client.registries.list())
            
            for r in registry_list:
                rg = r.id.split('/')[4]
                acrs.append({
                    'subscription_id': sub.subscription_id,
                    'resource_group': rg,
                    'acr_name': r.name,
                    'location': r.location,
                    'sku': r.sku.name,
                    'admin_user_enabled': r.admin_user_enabled,
                    'public_access': r.public_network_access != 'Disabled'
                })
                
        except Exception as e:
            utils.handle_azure_error(e, "ACR Discovery", f"Sub: {sub.subscription_id}")
            continue
    
    if acrs:
        filepath = os.path.join(output_dir, 'acrs.csv')
        with open(filepath, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=acrs[0].keys())
            writer.writeheader()
            writer.writerows(acrs)
        print(f"{Fore.GREEN}✓ Found {len(acrs)} ACRs → {filepath}{Style.RESET_ALL}")
    else:
        print(f"{Fore.YELLOW}No ACRs found.{Style.RESET_ALL}")
    
    return acrs

def main():
    parser = argparse.ArgumentParser(description="Discover AKS clusters and ACRs")
    parser.add_argument("--output", default="./inventory", help="Output directory for CSV files")
    args = parser.parse_args()
    
    os.makedirs(args.output, exist_ok=True)
    
    print(f"\n{Fore.CYAN}{'='*60}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}   AKS/ACR Discovery - {datetime.now().strftime('%Y-%m-%d %H:%M')}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{'='*60}{Style.RESET_ALL}\n")
    
    cred = utils.get_credential()
    subs = utils.get_target_subscriptions(cred)
    
    print(f"Found {len(subs)} accessible subscription(s)\n")
    
    discover_clusters(cred, subs, args.output)
    discover_acrs(cred, subs, args.output)
    
    print(f"\n{Fore.CYAN}{'='*60}{Style.RESET_ALL}")
    print(f"Discovery complete. Files saved to: {args.output}/")

if __name__ == "__main__":
    main()
