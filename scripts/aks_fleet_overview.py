#!/usr/bin/env python3
"""
AKS Fleet Overview Script
=========================
This script provides a high-level inventory of all AKS clusters accessible to the current user.
It iterates through subscriptions and resource groups to find Managed Clusters and reports key
architectural details.

Usage:
    python aks_fleet_overview.py [--subscription <subscription_id>]

Dependencies:
    pip install -r requirements.txt
"""

import argparse
import sys
from azure.identity import DefaultAzureCredential
from azure.mgmt.containerservice import ContainerServiceClient
import utils

init(autoreset=True)

def analyze_cluster(cluster):
    """Extracts key metrics from a ManagedCluster object."""
    
    # Determine Power State
    power_state = "Running"
    if cluster.power_state and cluster.power_state.code:
        power_state = cluster.power_state.code
    
    power_color = Fore.GREEN if power_state == "Running" else Fore.YELLOW

    # Network Profile
    net_plugin = "Unknown"
    net_policy = "None"
    if cluster.network_profile:
        net_plugin = cluster.network_profile.network_plugin or "Unknown"
        net_policy = cluster.network_profile.network_policy or "None"

    # Node Count
    agent_pool_count = len(cluster.agent_pool_profiles) if cluster.agent_pool_profiles else 0
    total_nodes = sum(p.count for p in cluster.agent_pool_profiles) if cluster.agent_pool_profiles else 0

    # API Server Access
    access_type = f"{Fore.RED}Public{Style.RESET_ALL}"
    if cluster.api_server_access_profile and cluster.api_server_access_profile.enable_private_cluster:
        access_type = f"{Fore.GREEN}Private{Style.RESET_ALL}"

    return [
        cluster.name,
        cluster.location,
        cluster.resource_group,
        cluster.kubernetes_version,
        f"{power_color}{power_state}{Style.RESET_ALL}",
        f"{net_plugin}/{net_policy}",
        access_type,
        total_nodes
    ]

def main():
    parser = argparse.ArgumentParser(description="AKS Fleet Overview")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Filter by specific subscription ID")
    args = parser.parse_args()

    credential = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None

    subscriptions = utils.get_target_subscriptions(credential, config, args.subscription)

    all_clusters_data = []
    headers = ["Cluster Name", "Location", "Resource Group", "K8s Ver", "State", "Network", "Access", "Nodes"]

    for sub in subscriptions:
        sub_id = sub.subscription_id
        # print(f"Scanning Subscription: {sub.display_name} ({sub_id})")
        
        try:
            aks_client = ContainerServiceClient(credential, sub_id)
            clusters = list(aks_client.managed_clusters.list())
            
            for cluster in clusters:
                # Check Utils Filtering
                rg_name = cluster.id.split('/')[4] # Parse RGs usually
                if not cluster.resource_group:
                   cluster.resource_group = rg_name

                if not utils.should_process_resource_group(rg_name, sub_id, config):
                    continue
                if not utils.should_process_cluster(cluster.name, sub_id, config):
                    continue

                all_clusters_data.append(analyze_cluster(cluster))

        except Exception as e:
            print(f"{Fore.YELLOW}Skipping subscription {sub_id} due to error: {e}{Style.RESET_ALL}")
            continue

    if not all_clusters_data:
        print(f"\n{Fore.YELLOW}No AKS clusters found.{Style.RESET_ALL}")
    else:
        print("\n" + tabulate(all_clusters_data, headers=headers, tablefmt="grid"))

if __name__ == "__main__":
    main()
