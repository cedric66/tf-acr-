#!/usr/bin/env python3
"""
AKS Network Audit
=================
Audits the network configuration of AKS clusters including VNet, Subnet, and IP usage.

Usage:
    python aks_network_audit.py [--config config.json] [--subscription sub_id]
"""

import argparse
from azure.mgmt.containerservice import ContainerServiceClient
from azure.mgmt.network import NetworkManagementClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def parse_subnet_id(subnet_id):
    """Extracts VNet and Subnet names from a subnet resource ID."""
    if not subnet_id:
        return None, None, None, None
    parts = subnet_id.split('/')
    # /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}
    try:
        sub_id = parts[2]
        rg = parts[4]
        vnet = parts[8]
        subnet = parts[10]
        return sub_id, rg, vnet, subnet
    except IndexError:
        return None, None, None, None

def get_subnet_usage(network_client, rg, vnet_name, subnet_name):
    """Gets IP usage for a subnet."""
    try:
        subnet = network_client.subnets.get(rg, vnet_name, subnet_name)
        # Count available IPs
        # address_prefix is like "10.0.0.0/24"
        prefix = subnet.address_prefix
        if prefix:
            # Calculate total IPs (minus 5 reserved by Azure)
            cidr = int(prefix.split('/')[1])
            total_ips = (2 ** (32 - cidr)) - 5
            used_ips = len(subnet.ip_configurations) if subnet.ip_configurations else 0
            usage_pct = (used_ips / total_ips * 100) if total_ips > 0 else 0
            return total_ips, used_ips, usage_pct
    except Exception as e:
        utils.handle_azure_error(e, "Subnet", f"{vnet_name}/{subnet_name}")
    return 0, 0, 0

def main():
    parser = argparse.ArgumentParser(description="AKS Network Audit")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["Cluster", "VNet", "Subnet", "CIDR", "Used/Total IPs", "Usage %", "Status"]

    for sub in subs:
        try:
            aks_client = ContainerServiceClient(cred, sub.subscription_id)
            network_client = NetworkManagementClient(cred, sub.subscription_id)
            
            clusters = list(aks_client.managed_clusters.list())
            
            for cluster in clusters:
                rg_name = cluster.id.split('/')[4]
                if not utils.should_process_resource_group(rg_name, sub.subscription_id, config):
                    continue
                if not utils.should_process_cluster(cluster.name, sub.subscription_id, config):
                    continue

                # Get subnet from agent pool profile
                subnet_id = None
                if cluster.agent_pool_profiles:
                    subnet_id = cluster.agent_pool_profiles[0].vnet_subnet_id
                
                if not subnet_id:
                    data.append([cluster.name, "N/A", "N/A", "N/A", "N/A", "N/A", f"{Fore.YELLOW}Kubenet?{Style.RESET_ALL}"])
                    continue

                subnet_sub, subnet_rg, vnet_name, subnet_name = parse_subnet_id(subnet_id)
                
                # Get Subnet details
                try:
                    subnet = network_client.subnets.get(subnet_rg, vnet_name, subnet_name)
                    cidr = subnet.address_prefix
                    total, used, pct = get_subnet_usage(network_client, subnet_rg, vnet_name, subnet_name)
                    
                    status = f"{Fore.GREEN}OK{Style.RESET_ALL}"
                    if pct > 80:
                        status = f"{Fore.RED}HIGH USAGE{Style.RESET_ALL}"
                    elif pct > 60:
                        status = f"{Fore.YELLOW}MEDIUM{Style.RESET_ALL}"
                    
                    data.append([
                        cluster.name,
                        vnet_name,
                        subnet_name,
                        cidr,
                        f"{used}/{total}",
                        f"{pct:.1f}%",
                        status
                    ])
                except Exception as e:
                    utils.handle_azure_error(e, "Subnet", f"{vnet_name}/{subnet_name}")
                    data.append([cluster.name, vnet_name, subnet_name, "?", "?", "?", f"{Fore.RED}ERROR{Style.RESET_ALL}"])

        except Exception as e:
            if not utils.handle_azure_error(e, "AKS Clusters", f"Subscription: {sub.subscription_id}"):
                break  # Fatal error, stop processing
            continue

    if not data:
        print(f"{Fore.YELLOW}No clusters found or no network data available.{Style.RESET_ALL}")
    else:
        print(tabulate(data, headers=headers, tablefmt="grid"))

if __name__ == "__main__":
    main()
