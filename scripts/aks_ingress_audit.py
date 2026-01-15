#!/usr/bin/env python3
"""
AKS Ingress Audit
=================
Audits ingress configuration on AKS clusters, focusing on Application Gateway (AGIC) and WAF.

Usage:
    python aks_ingress_audit.py [--config config.json] [--subscription sub_id]
"""

import argparse
from azure.mgmt.containerservice import ContainerServiceClient
from azure.mgmt.network import NetworkManagementClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def check_ingress_addons(cluster):
    """Checks for ingress-related add-ons on the cluster."""
    addons = cluster.addon_profiles or {}
    
    # AGIC (Application Gateway Ingress Controller)
    agic = addons.get('ingressApplicationGateway', {})
    agic_enabled = agic.get('enabled', False) if agic else False
    agic_gw_id = agic.get('config', {}).get('applicationGatewayId', '') if agic else ''
    
    # HTTP Application Routing (deprecated)
    http_routing = addons.get('httpApplicationRouting', {})
    http_enabled = http_routing.get('enabled', False) if http_routing else False
    
    return agic_enabled, agic_gw_id, http_enabled

def get_appgw_waf_status(network_client, appgw_id):
    """Checks if the Application Gateway has WAF enabled."""
    if not appgw_id:
        return "N/A", "N/A"
    
    try:
        # Parse AppGW ID
        parts = appgw_id.split('/')
        rg = parts[4]
        appgw_name = parts[8]
        
        appgw = network_client.application_gateways.get(rg, appgw_name)
        
        # Check SKU for WAF tier
        sku = appgw.sku.tier if appgw.sku else "Unknown"
        waf_enabled = "WAF" in sku.upper() if sku else False
        
        # Check WAF configuration
        waf_config = appgw.web_application_firewall_configuration
        if waf_config and waf_config.enabled:
            mode = waf_config.firewall_mode  # Prevention or Detection
            return f"{Fore.GREEN}Enabled ({mode}){Style.RESET_ALL}", sku
        elif waf_enabled:
            return f"{Fore.YELLOW}SKU=WAF, Config Disabled{Style.RESET_ALL}", sku
        else:
            return f"{Fore.RED}No WAF{Style.RESET_ALL}", sku
            
    except Exception as e:
        utils.handle_azure_error(e, "Application Gateway", appgw_id.split('/')[-1] if appgw_id else "")
        return "Error", "?"

def main():
    parser = argparse.ArgumentParser(description="AKS Ingress Audit")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["Cluster", "AGIC", "App Gateway", "WAF Status", "HTTP Routing (Deprecated)"]

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

                agic_enabled, agic_gw_id, http_enabled = check_ingress_addons(cluster)
                
                agic_status = f"{Fore.GREEN}Enabled{Style.RESET_ALL}" if agic_enabled else f"{Fore.YELLOW}Disabled{Style.RESET_ALL}"
                http_status = f"{Fore.RED}Enabled (Deprecated!){Style.RESET_ALL}" if http_enabled else "Disabled"
                
                appgw_name = agic_gw_id.split('/')[-1] if agic_gw_id else "N/A"
                waf_status, _ = get_appgw_waf_status(network_client, agic_gw_id) if agic_gw_id else ("N/A", "N/A")
                
                data.append([
                    cluster.name,
                    agic_status,
                    appgw_name,
                    waf_status,
                    http_status
                ])

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
