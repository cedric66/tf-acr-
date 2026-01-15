#!/usr/bin/env python3
"""
AKS Backup Audit
================
Checks if Azure Backup for AKS is enabled on clusters.
Note: Cannot detect Velero without kubectl access.

Usage:
    python aks_backup_audit.py [--config config.json] [--subscription sub_id]
"""

import argparse
import subprocess
import json
from azure.mgmt.containerservice import ContainerServiceClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def check_backup_extension(cluster_name, rg_name, sub_id):
    """Uses AZ CLI to check for backup extension (SDK for extensions is complex)."""
    try:
        cmd = [
            "az", "k8s-extension", "list",
            "--cluster-name", cluster_name,
            "--resource-group", rg_name,
            "--cluster-type", "managedClusters",
            "--subscription", sub_id,
            "--output", "json"
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode != 0:
            # Extension command may fail if no extensions or permission issue
            if "AuthorizationFailed" in result.stderr:
                return "Permission Denied"
            return "No Extensions"
        
        extensions = json.loads(result.stdout)
        for ext in extensions:
            ext_type = ext.get('extensionType', '').lower()
            if 'backup' in ext_type or ext.get('name', '').lower() == 'azure-aks-backup':
                return f"{Fore.GREEN}Enabled{Style.RESET_ALL}"
        
        return f"{Fore.YELLOW}Not Configured{Style.RESET_ALL}"
        
    except subprocess.TimeoutExpired:
        return "Timeout"
    except Exception as e:
        return f"Error: {str(e)[:30]}"

def main():
    parser = argparse.ArgumentParser(description="AKS Backup Audit")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["Cluster", "RG", "Backup Extension", "Notes"]

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

                backup_status = check_backup_extension(cluster.name, rg_name, sub.subscription_id)
                
                notes = ""
                if backup_status == "Not Configured":
                    notes = "Consider enabling Azure Backup for AKS"
                
                data.append([cluster.name, rg_name, backup_status, notes])

        except Exception as e:
            if not utils.handle_azure_error(e, "AKS Clusters", f"Subscription: {sub.subscription_id}"):
                break
            continue

    if not data:
        print(f"{Fore.YELLOW}No clusters found.{Style.RESET_ALL}")
    else:
        print(tabulate(data, headers=headers, tablefmt="grid"))
        print(f"\n{Fore.CYAN}Note:{Style.RESET_ALL} Velero (in-cluster backup) cannot be detected without kubectl access.")

if __name__ == "__main__":
    main()
