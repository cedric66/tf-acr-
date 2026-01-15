#!/usr/bin/env python3
"""
AKS Fleet Overview Script
=========================
Provides a high-level inventory of all AKS clusters accessible to the current user.

Usage:
    python aks_fleet_overview.py [--subscription <sub_id>] [--output json]

Examples:
    # Interactive table output
    python aks_fleet_overview.py

    # JSON output for automation
    python aks_fleet_overview.py --output json

    # Target specific subscription
    python aks_fleet_overview.py --subscription abc-123 --output json
"""
from __future__ import annotations

import argparse
from typing import List, Dict, Any

from azure.mgmt.containerservice import ContainerServiceClient
from tabulate import tabulate
from colorama import init, Fore, Style

import utils

init(autoreset=True)


def analyze_cluster(cluster) -> Dict[str, Any]:
    """
    Extracts key metrics from a ManagedCluster object.
    
    Returns a dictionary with cluster information.
    """
    # Determine Power State
    power_state = "Running"
    if cluster.power_state and cluster.power_state.code:
        power_state = cluster.power_state.code
    
    # Network Profile
    net_plugin = "Unknown"
    net_policy = "None"
    if cluster.network_profile:
        net_plugin = cluster.network_profile.network_plugin or "Unknown"
        net_policy = cluster.network_profile.network_policy or "None"

    # Node Count
    total_nodes = sum(p.count for p in cluster.agent_pool_profiles) if cluster.agent_pool_profiles else 0
    pool_count = len(cluster.agent_pool_profiles) if cluster.agent_pool_profiles else 0

    # API Server Access
    is_private = False
    if cluster.api_server_access_profile and cluster.api_server_access_profile.enable_private_cluster:
        is_private = True

    # Resource Group from ID
    rg_name = cluster.id.split('/')[4] if cluster.id else "Unknown"

    return {
        "cluster_name": cluster.name,
        "location": cluster.location,
        "resource_group": rg_name,
        "kubernetes_version": cluster.kubernetes_version,
        "power_state": power_state,
        "network_plugin": net_plugin,
        "network_policy": net_policy,
        "private_cluster": is_private,
        "node_count": total_nodes,
        "pool_count": pool_count
    }


def format_for_table(cluster_data: Dict[str, Any]) -> List[str]:
    """Formats cluster data for table display with colors."""
    power_state = cluster_data['power_state']
    power_color = Fore.GREEN if power_state == "Running" else Fore.YELLOW
    
    access_type = f"{Fore.GREEN}Private{Style.RESET_ALL}" if cluster_data['private_cluster'] else f"{Fore.RED}Public{Style.RESET_ALL}"
    
    return [
        cluster_data['cluster_name'],
        cluster_data['location'],
        cluster_data['resource_group'],
        cluster_data['kubernetes_version'],
        f"{power_color}{power_state}{Style.RESET_ALL}",
        f"{cluster_data['network_plugin']}/{cluster_data['network_policy']}",
        access_type,
        cluster_data['node_count']
    ]


@utils.retry_on_throttle(max_retries=3)
def list_clusters(client: ContainerServiceClient):
    """Lists all managed clusters with retry on throttling."""
    return list(client.managed_clusters.list())


def main():
    parser = argparse.ArgumentParser(description="AKS Fleet Overview")
    utils.add_common_args(parser)
    args = parser.parse_args()
    
    # Initialize output format
    utils.init_from_args(args)

    credential = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subscriptions = utils.get_target_subscriptions(credential, config, args.subscription)

    all_clusters: List[Dict[str, Any]] = []
    headers = ["Cluster Name", "Location", "Resource Group", "K8s Ver", "State", "Network", "Access", "Nodes"]

    for sub in subscriptions:
        try:
            aks_client = ContainerServiceClient(credential, sub.subscription_id)
            clusters = list_clusters(aks_client)
            
            for cluster in clusters:
                rg_name = cluster.id.split('/')[4]
                
                if not utils.should_process_resource_group(rg_name, sub.subscription_id, config):
                    continue
                if not utils.should_process_cluster(cluster.name, sub.subscription_id, config):
                    continue

                cluster_data = analyze_cluster(cluster)
                cluster_data['subscription_id'] = sub.subscription_id
                all_clusters.append(cluster_data)

        except Exception as e:
            utils.handle_azure_error(e, "AKS Clusters", f"Subscription: {sub.subscription_id}")
            continue

    # Output results
    if utils.is_json_output():
        utils.output_results(all_clusters)
    else:
        if not all_clusters:
            print(f"\n{Fore.YELLOW}No AKS clusters found.{Style.RESET_ALL}")
        else:
            table_data = [format_for_table(c) for c in all_clusters]
            print("\n" + tabulate(table_data, headers=headers, tablefmt="grid"))
            print(f"\n{Fore.CYAN}Total: {len(all_clusters)} cluster(s){Style.RESET_ALL}")


if __name__ == "__main__":
    main()
