#!/usr/bin/env python3
"""
AKS Cost Auditor Script
=======================
This script inspects AKS node pools to identify potential cost savings and optimization opportunities.
It looks for low-utilization pools, opportunities for Spot instances, and expensive OS SKUs.

Usage:
    python aks_cost_auditor.py [--subscription <subscription_id>]

Dependencies:
    pip install -r requirements.txt
"""

import argparse
import sys
from azure.identity import DefaultAzureCredential
from azure.mgmt.containerservice import ContainerServiceClient
import utils
# from azure.mgmt.resource import SubscriptionClient 
from tabulate import tabulate
from colorama import init, Fore, Style

init(autoreset=True)

def audit_cluster(cluster):
    findings = []
    
    if not cluster.agent_pool_profiles:
        return []

    for pool in cluster.agent_pool_profiles:
        pool_name = pool.name
        mode = pool.mode # System or User
        vm_size = pool.vm_size
        count = pool.count
        os_type = pool.os_type
        # Spot vs Regular
        scale_set_priority = pool.scale_set_priority or "Regular"
        
        # 1. Spot Instance Opportunity
        # If a User pool is strictly "Regular", it might be a candidate for Spot if it's for DEV/Test
        spot_status = f"{Fore.GREEN}SPOT{Style.RESET_ALL}" if scale_set_priority == "Spot" else "Regular"
        
        recommendation = ""
        
        # Check: User pool with fixed high count
        if mode == "User" and scale_set_priority == "Regular" and count > 2:
            recommendation += f"{Fore.YELLOW}Consider Spot? {Style.RESET_ALL}"

        # Check: System pool sizing
        if mode == "System" and count > 3:
             recommendation += "High System Node Count. "

        # Check: Windows License Cost
        if os_type == "Windows":
             recommendation += f"{Fore.YELLOW}Windows Lic Cost. {Style.RESET_ALL}"

        # Check: Auto-scaling
        autoscaling = "Enabled" if pool.enable_auto_scaling else f"{Fore.YELLOW}Fixed{Style.RESET_ALL}"
        if not pool.enable_auto_scaling and mode == "User" and count > 0:
             recommendation += "Enable Autoscaler? "

        findings.append([
            cluster.name,
            pool_name,
            mode,
            vm_size,
            count,
            spot_status,
            autoscaling,
            recommendation
        ])

    return findings

def main():
    parser = argparse.ArgumentParser(description="AKS Cost Auditor")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Filter by specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None

    subscriptions = utils.get_target_subscriptions(cred, config, args.subscription)

    all_findings = []
    headers = ["Cluster", "Pool", "Mode", "SKU", "Count", "Priority", "Scaling", "Notes"]

    for sub in subscriptions:
        sub_id = sub.subscription_id
        try:
            aks_client = ContainerServiceClient(cred, sub_id)
            clusters = list(aks_client.managed_clusters.list())
            
            for cluster in clusters:
                rg_name = cluster.id.split('/')[4]
                if not utils.should_process_resource_group(rg_name, sub_id, config):
                    continue
                if not utils.should_process_cluster(cluster.name, sub_id, config):
                    continue

                cluster_findings = audit_cluster(cluster)
                all_findings.extend(cluster_findings)

        except Exception as e:
            continue

    if not all_findings:
        print(f"\n{Fore.GREEN}No obvious cost anomalies found (or no clusters reachable).{Style.RESET_ALL}")
    else:
        print("\n" + tabulate(all_findings, headers=headers, tablefmt="grid"))

if __name__ == "__main__":
    main()
