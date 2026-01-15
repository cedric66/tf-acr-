#!/usr/bin/env python3
"""
ACR Inventory Script
====================
Inventories Azure Container Registries and checks for Admin User setting (security risk).

Usage:
    python acr_inventory.py [--config config.json] [--subscription sub_id]
"""

import argparse
from azure.mgmt.containerregistry import ContainerRegistryManagementClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def analyze_acr(acr):
    # Admin User Check
    admin_enabled = acr.admin_user_enabled
    admin_status = f"{Fore.RED}Enabled{Style.RESET_ALL}" if admin_enabled else f"{Fore.GREEN}Disabled{Style.RESET_ALL}"

    # SKU
    sku = acr.sku.name
    
    # Public Access
    public_access = "Enabled"
    if acr.public_network_access == "Disabled":
        public_access = f"{Fore.GREEN}Disabled{Style.RESET_ALL}"
    
    return [
        acr.name,
        acr.location,
        sku,
        admin_status,
        public_access,
        acr.creation_date.strftime('%Y-%m-%d') if acr.creation_date else "N/A"
    ]

def main():
    parser = argparse.ArgumentParser(description="ACR Inventory")
    parser.add_argument("--config", help="Path to JSON config file for targets")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["ACR Name", "Location", "SKU", "Admin User", "Public Access", "Created"]

    for sub in subs:
        try:
            client = ContainerRegistryManagementClient(cred, sub.subscription_id)
            registries = client.registries.list()
            for acr in registries:
                # Basic resource group filtering handled by `list` scope (all in sub), 
                # strictly speaking, we could filter by RG using utils.should_process_resource_group
                # if we parsed the ID, but for ACR global listing is usually preferred.
                data.append(analyze_acr(acr))
        except Exception as e:
            # print(f"Error in sub {sub.subscription_id}: {e}")
            continue

    if not data:
        print(f"{Fore.YELLOW}No ACRs found.{Style.RESET_ALL}")
    else:
        print(tabulate(data, headers=headers, tablefmt="grid"))

if __name__ == "__main__":
    main()
