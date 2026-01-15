#!/usr/bin/env python3
"""
ACR Replication Audit
=====================
Audits geo-replication status for Premium ACRs.

Usage:
    python acr_replication_audit.py [--config config.json] [--subscription sub_id]
"""

import argparse
from azure.mgmt.containerregistry import ContainerRegistryManagementClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def get_replications(acr_client, rg_name, acr_name, sku):
    """Gets replication status for an ACR."""
    if sku.lower() != 'premium':
        return []
    
    try:
        replications = list(acr_client.replications.list(rg_name, acr_name))
        result = []
        for rep in replications:
            status = rep.status.display_status if rep.status else "Unknown"
            result.append({
                'location': rep.location,
                'status': status
            })
        return result
    except Exception as e:
        utils.handle_azure_error(e, "ACR Replications", acr_name)
        return []

def main():
    parser = argparse.ArgumentParser(description="ACR Replication Audit")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["ACR", "SKU", "Primary Location", "Replicated Locations", "Status"]

    for sub in subs:
        try:
            acr_client = ContainerRegistryManagementClient(cred, sub.subscription_id)
            registries = list(acr_client.registries.list())
            
            for acr in registries:
                sku = acr.sku.name
                rg_name = acr.id.split('/')[4]
                
                if sku.lower() == 'premium':
                    replications = get_replications(acr_client, rg_name, acr.name, sku)
                    
                    if replications:
                        # Filter out primary location
                        secondary = [r for r in replications if r['location'].lower() != acr.location.lower()]
                        
                        if secondary:
                            locations = ", ".join([r['location'] for r in secondary])
                            statuses = set(r['status'] for r in secondary)
                            status_str = f"{Fore.GREEN}Ready{Style.RESET_ALL}" if all(s == 'Ready' for s in statuses) else f"{Fore.YELLOW}Syncing{Style.RESET_ALL}"
                        else:
                            locations = f"{Fore.YELLOW}None (Single Region){Style.RESET_ALL}"
                            status_str = "N/A"
                    else:
                        locations = f"{Fore.YELLOW}Not Configured{Style.RESET_ALL}"
                        status_str = "N/A"
                else:
                    locations = f"{Fore.CYAN}N/A (Not Premium){Style.RESET_ALL}"
                    status_str = "-"
                
                data.append([
                    acr.name,
                    sku,
                    acr.location,
                    locations,
                    status_str
                ])

        except Exception as e:
            if not utils.handle_azure_error(e, "ACR Registries", f"Subscription: {sub.subscription_id}"):
                break
            continue

    if not data:
        print(f"{Fore.YELLOW}No ACRs found.{Style.RESET_ALL}")
    else:
        print(tabulate(data, headers=headers, tablefmt="grid"))
        print(f"\n{Fore.CYAN}Note:{Style.RESET_ALL} Geo-replication is only available for Premium SKU.")

if __name__ == "__main__":
    main()
