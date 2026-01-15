#!/usr/bin/env python3
"""
AKS Disk Auditor (Orphaned PVC Finder)
=====================================
finds Managed Disks that are 'Unattached' and likely left over from deleted PVCs or Clusters.

Usage:
    python aks_disk_auditor.py [--config config.json] [--subscription sub_id] [--delete-dry-run]
"""

import argparse
from azure.mgmt.compute import ComputeManagementClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def audit_disks(compute_client, rg_name, sub_id):
    orphans = []
    
    # List all disks in the RG
    disks = compute_client.disks.list_by_resource_group(rg_name)
    
    for disk in disks:
        if disk.disk_state == "Unattached":
            # Heuristics for AKS / Kubernets Origin
            is_k8s = False
            if disk.tags and 'kubernetes.io-created-for-pv-name' in disk.tags:
                is_k8s = True
            elif "MC_" in rg_name: # Common AKS naming pattern
                is_k8s = True
            elif disk.name.startswith("kubernetes-dynamic-"):
                is_k8s = True
                
            cost_hint = f"{disk.disk_size_gb}GB ({disk.sku.name})"
            
            orphans.append([
                disk.name,
                rg_name,
                cost_hint,
                f"{Fore.RED}Unattached{Style.RESET_ALL}",
                f"{Fore.YELLOW}Yes{Style.RESET_ALL}" if is_k8s else "No",
                disk.time_created.strftime('%Y-%m-%d') if disk.time_created else "N/A"
            ])
            
    return orphans

def main():
    parser = argparse.ArgumentParser(description="AKS Disk Auditor")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["Disk Name", "RG", "Size/SKU", "State", "Likely K8s Orphan?", "Created"]

    for sub in subs:
        try:
            compute_client = ComputeManagementClient(cred, sub.subscription_id)
            
            # Optimization: If config specifies RGs, only list in those. 
            # Otherwise we have to list ALL RGs in Sub to find disks? 
            # Wait, list_by_resource_group requires RG name.
            # list() method on disks lists ALL in subscription. Better/Faster.
            
            all_disks = list(compute_client.disks.list())
            for disk in all_disks:
                 # Check Filter
                rg_name = disk.id.split('/')[4]
                if not utils.should_process_resource_group(rg_name, sub.subscription_id, config):
                    continue

                if disk.disk_state == "Unattached":
                     is_k8s = False
                     tags = disk.tags or {}
                     if 'kubernetes.io-created-for-pv-name' in tags:
                         is_k8s = True
                     elif "MC_" in rg_name:
                         is_k8s = True
                     elif disk.name.startswith("kubernetes-dynamic-"):
                         is_k8s = True
                    
                     data.append([
                        disk.name,
                        rg_name,
                        f"{disk.disk_size_gb}GB ({disk.sku.name})",
                        f"{Fore.RED}Unattached{Style.RESET_ALL}",
                        f"{Fore.YELLOW}Yes{Style.RESET_ALL}" if is_k8s else "No",
                        disk.time_created.strftime('%Y-%m-%d') if disk.time_created else "N/A"
                     ])

        except Exception as e:
            # print(f"Error in sub {sub.subscription_id}: {e}")
            continue

    if not data:
        print(f"{Fore.GREEN}No orphaned disks found.{Style.RESET_ALL}")
    else:
        print(tabulate(data, headers=headers, tablefmt="grid"))

if __name__ == "__main__":
    main()
