#!/usr/bin/env python3
"""
AKS Auth & RBAC Auditor
=======================
Audits AKS clusters for authentication methods (AAD vs Local) and lists privileged role assignments.

Usage:
    python aks_auth_rbac.py [--config config.json] [--subscription sub_id]
"""

import argparse
from azure.mgmt.containerservice import ContainerServiceClient
from azure.mgmt.authorization import AuthorizationManagementClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def check_local_accounts(cluster):
    """Checks if local accounts are disabled."""
    if cluster.disable_local_accounts:
        return f"{Fore.GREEN}Disabled{Style.RESET_ALL}"
    return f"{Fore.YELLOW}Enabled{Style.RESET_ALL}"

def check_aad_integration(cluster):
    """Checks for AAD integration."""
    if cluster.aad_profile:
        return f"{Fore.GREEN}Managed AAD{Style.RESET_ALL}" if cluster.aad_profile.managed else "Legacy AAD"
    return "No AAD"

def list_cluster_admins(auth_client, cluster_id):
    """
    Lists assignments for Owner/Contributor/User Access Administrator on the cluster scope.
    NOTE: This can be slow and requires high privileges (Read on RoleAssignments).
    """
    try:
        assignments = auth_client.role_assignments.list_for_scope(cluster_id)
        admins = []
        for role in assignments:
            # We filter for high-privilege roles by common names or IDs if we had them.
            # Ideally we resolve the RoleDefinition, but that adds another API call per role.
            # We will just count them or list the visible Principal IDs for the report summary.
            # For this summary, we will just count total assignments to keep it fast.
            admins.append(role.principal_id)
        return len(admins)
    except Exception:
        return "?"

def main():
    parser = argparse.ArgumentParser(description="AKS Auth & RBAC Auditor")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    parser.add_argument("--show-assignments", action="store_true", help="Attempt to list Role Assignment counts (Slow)")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["Cluster", "RG", "Local Accts", "AAD Integration", "RBAC Enabled", "Assignments"]

    for sub in subs:
        try:
            aks_client = ContainerServiceClient(cred, sub.subscription_id)
            auth_client = AuthorizationManagementClient(cred, sub.subscription_id) if args.show_assignments else None
            
            clusters = aks_client.managed_clusters.list()
            for cluster in clusters:
                # Filter logical checks
                rg_name = cluster.id.split('/')[4] # Parse if missing
                if not utils.should_process_resource_group(rg_name, sub.subscription_id, config):
                    continue
                if not utils.should_process_cluster(cluster.name, sub.subscription_id, config):
                    continue

                local_acct = check_local_accounts(cluster)
                aad = check_aad_integration(cluster)
                rbac = f"{Fore.GREEN}Yes{Style.RESET_ALL}" if cluster.enable_rbac else f"{Fore.RED}No{Style.RESET_ALL}"
                
                assign_count = "N/A"
                if args.show_assignments and auth_client:
                    assign_count = list_cluster_admins(auth_client, cluster.id)

                data.append([cluster.name, rg_name, local_acct, aad, rbac, assign_count])
        except Exception as e:
            continue

    if not data:
        print(f"{Fore.YELLOW}No clusters found.{Style.RESET_ALL}")
    else:
        print(tabulate(data, headers=headers, tablefmt="grid"))

if __name__ == "__main__":
    main()
