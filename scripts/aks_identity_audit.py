#!/usr/bin/env python3
"""
AKS Identity Audit
==================
Audits Managed Identity configuration on AKS clusters to ensure best practices.

Usage:
    python aks_identity_audit.py [--config config.json] [--subscription sub_id]
"""

import argparse
from azure.mgmt.containerservice import ContainerServiceClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def audit_identity(cluster):
    """Analyzes the identity configuration of a cluster."""
    
    # Check main identity type
    identity = cluster.identity
    identity_type = "Unknown"
    
    if identity:
        identity_type = identity.type  # SystemAssigned, UserAssigned, None
    
    # Check for legacy Service Principal
    sp = cluster.service_principal_profile
    uses_sp = False
    if sp and sp.client_id and sp.client_id != "msi":
        uses_sp = True
    
    # Check Kubelet identity (for ACR pulls etc)
    kubelet_identity = None
    if cluster.identity_profile:
        kubelet_id = cluster.identity_profile.get('kubeletidentity', {})
        if kubelet_id:
            kubelet_identity = kubelet_id.client_id if hasattr(kubelet_id, 'client_id') else kubelet_id.get('clientId')
    
    # Check for local accounts disabled
    local_disabled = cluster.disable_local_accounts or False
    
    return identity_type, uses_sp, kubelet_identity, local_disabled

def identity_status(identity_type, uses_sp):
    """Returns a formatted identity status."""
    if uses_sp:
        return f"{Fore.RED}Service Principal (Legacy){Style.RESET_ALL}"
    elif identity_type == "SystemAssigned":
        return f"{Fore.GREEN}System Managed Identity{Style.RESET_ALL}"
    elif identity_type == "UserAssigned":
        return f"{Fore.GREEN}User Managed Identity{Style.RESET_ALL}"
    else:
        return f"{Fore.YELLOW}{identity_type}{Style.RESET_ALL}"

def main():
    parser = argparse.ArgumentParser(description="AKS Identity Audit")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["Cluster", "Identity Type", "Kubelet Identity", "Local Accounts", "Recommendation"]

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

                id_type, uses_sp, kubelet_id, local_disabled = audit_identity(cluster)
                
                id_status = identity_status(id_type, uses_sp)
                kubelet_str = f"...{kubelet_id[-8:]}" if kubelet_id else f"{Fore.YELLOW}N/A{Style.RESET_ALL}"
                local_status = f"{Fore.GREEN}Disabled{Style.RESET_ALL}" if local_disabled else f"{Fore.YELLOW}Enabled{Style.RESET_ALL}"
                
                # Recommendations
                recs = []
                if uses_sp:
                    recs.append("Migrate to Managed Identity")
                if not local_disabled:
                    recs.append("Disable local accounts")
                
                rec_str = "; ".join(recs) if recs else f"{Fore.GREEN}OK{Style.RESET_ALL}"
                
                data.append([cluster.name, id_status, kubelet_str, local_status, rec_str])

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
