#!/usr/bin/env python3
"""
AKS/ACR Discovery Script
========================
Scans all accessible subscriptions and outputs CSV inventories.
These CSVs can be filtered and used as input for other audit scripts.

Usage:
    python discover.py [--output ./inventory/]
    python discover.py --output json  # JSON to stdout

Examples:
    # Generate CSV files
    python discover.py --dir ./inventory/

    # JSON output for piping to other tools
    python discover.py --output json | jq '.clusters'
"""
from __future__ import annotations

import argparse
import os
import csv
import json
from datetime import datetime
from typing import List, Dict, Any

from azure.mgmt.containerservice import ContainerServiceClient
from azure.mgmt.containerregistry import ContainerRegistryManagementClient
from colorama import init, Fore, Style

import utils

init(autoreset=True)


@utils.retry_on_throttle(max_retries=3)
def list_aks_clusters(client: ContainerServiceClient) -> List:
    """Lists all AKS clusters with retry on throttling."""
    return list(client.managed_clusters.list())


@utils.retry_on_throttle(max_retries=3)
def list_registries(client: ContainerRegistryManagementClient) -> List:
    """Lists all ACRs with retry on throttling."""
    return list(client.registries.list())


def discover_clusters(cred, subs: List[utils.SubscriptionInfo]) -> List[Dict[str, Any]]:
    """Discovers all AKS clusters across subscriptions."""
    clusters = []
    
    if not utils.is_json_output():
        print(f"{Fore.CYAN}Discovering AKS clusters...{Style.RESET_ALL}")
    
    for sub in subs:
        try:
            aks_client = ContainerServiceClient(cred, sub.subscription_id)
            cluster_list = list_aks_clusters(aks_client)
            
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
    
    if not utils.is_json_output():
        print(f"{Fore.GREEN}✓ Found {len(clusters)} clusters{Style.RESET_ALL}")
    
    return clusters


def discover_acrs(cred, subs: List[utils.SubscriptionInfo]) -> List[Dict[str, Any]]:
    """Discovers all ACRs across subscriptions."""
    acrs = []
    
    if not utils.is_json_output():
        print(f"{Fore.CYAN}Discovering Azure Container Registries...{Style.RESET_ALL}")
    
    for sub in subs:
        try:
            acr_client = ContainerRegistryManagementClient(cred, sub.subscription_id)
            registry_list = list_registries(acr_client)
            
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
    
    if not utils.is_json_output():
        print(f"{Fore.GREEN}✓ Found {len(acrs)} ACRs{Style.RESET_ALL}")
    
    return acrs


def write_csv(data: List[Dict[str, Any]], filepath: str) -> None:
    """Writes data to a CSV file."""
    if data:
        with open(filepath, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=data[0].keys())
            writer.writeheader()
            writer.writerows(data)


def main():
    parser = argparse.ArgumentParser(description="Discover AKS clusters and ACRs")
    parser.add_argument("--dir", default="./inventory", help="Output directory for CSV files")
    parser.add_argument(
        "--output", "-o",
        choices=["csv", "json"],
        default="csv",
        help="Output format: 'csv' (default) or 'json'"
    )
    args = parser.parse_args()
    
    # Set JSON output mode if specified
    if args.output == "json":
        utils.set_output_format("json")
    
    # Print header (only for CSV mode)
    if not utils.is_json_output():
        print(f"\n{Fore.CYAN}{'='*60}{Style.RESET_ALL}")
        print(f"{Fore.CYAN}   AKS/ACR Discovery - {datetime.now().strftime('%Y-%m-%d %H:%M')}{Style.RESET_ALL}")
        print(f"{Fore.CYAN}{'='*60}{Style.RESET_ALL}\n")
    
    cred = utils.get_credential()
    subs = utils.get_target_subscriptions(cred)
    
    if not utils.is_json_output():
        print(f"Found {len(subs)} accessible subscription(s)\n")
    
    clusters = discover_clusters(cred, subs)
    acrs = discover_acrs(cred, subs)
    
    if utils.is_json_output():
        # JSON output to stdout
        result = {
            "discovery_time": datetime.now().isoformat(),
            "subscription_count": len(subs),
            "clusters": clusters,
            "acrs": acrs
        }
        print(json.dumps(result, indent=2, default=str))
    else:
        # CSV output to files
        os.makedirs(args.dir, exist_ok=True)
        
        clusters_file = os.path.join(args.dir, 'clusters.csv')
        acrs_file = os.path.join(args.dir, 'acrs.csv')
        
        write_csv(clusters, clusters_file)
        write_csv(acrs, acrs_file)
        
        print(f"\n{Fore.CYAN}{'='*60}{Style.RESET_ALL}")
        print(f"Discovery complete. Files saved to: {args.dir}/")
        print(f"  • clusters.csv: {len(clusters)} clusters")
        print(f"  • acrs.csv: {len(acrs)} registries")
        print(f"\nNext: Filter CSVs as needed, then run audits.")
        print(f"{Fore.CYAN}{'='*60}{Style.RESET_ALL}")


if __name__ == "__main__":
    main()
