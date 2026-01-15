#!/usr/bin/env python3
"""
AKS Node Utilization
====================
Queries Azure Monitor for node-level CPU and Memory utilization.
Does NOT require kubectl access - uses Azure Monitor Metrics API.

Usage:
    python aks_node_utilization.py [--config config.json] [--subscription sub_id]
"""

import argparse
from datetime import datetime, timedelta, timezone
from azure.mgmt.containerservice import ContainerServiceClient
from azure.mgmt.monitor import MonitorManagementClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def get_cluster_metrics(monitor_client, cluster_id):
    """Fetches CPU and Memory metrics for the cluster from Azure Monitor."""
    try:
        # Time range: last 1 hour
        end_time = datetime.now(timezone.utc)
        start_time = end_time - timedelta(hours=1)
        timespan = f"{start_time.isoformat()}/{end_time.isoformat()}"
        
        # Metric names for Managed Clusters
        # node_cpu_usage_percentage, node_memory_rss_percentage
        metrics = monitor_client.metrics.list(
            resource_uri=cluster_id,
            timespan=timespan,
            interval='PT5M',
            metricnames='node_cpu_usage_percentage,node_memory_rss_percentage',
            aggregation='Average'
        )
        
        cpu_avg = None
        mem_avg = None
        
        for item in metrics.value:
            if item.name.value == 'node_cpu_usage_percentage':
                for ts in item.timeseries:
                    for dp in ts.data:
                        if dp.average is not None:
                            cpu_avg = dp.average
            elif item.name.value == 'node_memory_rss_percentage':
                for ts in item.timeseries:
                    for dp in ts.data:
                        if dp.average is not None:
                            mem_avg = dp.average
        
        return cpu_avg, mem_avg
        
    except Exception as e:
        utils.handle_azure_error(e, "Metrics", cluster_id.split('/')[-1])
        return None, None

def utilization_status(value):
    """Color-codes utilization percentage."""
    if value is None:
        return f"{Fore.YELLOW}N/A{Style.RESET_ALL}"
    if value > 80:
        return f"{Fore.RED}{value:.1f}%{Style.RESET_ALL}"
    elif value > 60:
        return f"{Fore.YELLOW}{value:.1f}%{Style.RESET_ALL}"
    else:
        return f"{Fore.GREEN}{value:.1f}%{Style.RESET_ALL}"

def main():
    parser = argparse.ArgumentParser(description="AKS Node Utilization")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["Cluster", "CPU (avg 1h)", "Memory (avg 1h)", "Status"]

    for sub in subs:
        try:
            aks_client = ContainerServiceClient(cred, sub.subscription_id)
            monitor_client = MonitorManagementClient(cred, sub.subscription_id)
            
            clusters = list(aks_client.managed_clusters.list())
            
            for cluster in clusters:
                rg_name = cluster.id.split('/')[4]
                if not utils.should_process_resource_group(rg_name, sub.subscription_id, config):
                    continue
                if not utils.should_process_cluster(cluster.name, sub.subscription_id, config):
                    continue

                cpu, mem = get_cluster_metrics(monitor_client, cluster.id)
                
                cpu_str = utilization_status(cpu)
                mem_str = utilization_status(mem)
                
                # Overall status
                if cpu is None or mem is None:
                    status = f"{Fore.YELLOW}No Metrics{Style.RESET_ALL}"
                elif cpu > 80 or mem > 80:
                    status = f"{Fore.RED}High Load{Style.RESET_ALL}"
                elif cpu < 20 and mem < 20:
                    status = f"{Fore.YELLOW}Under-utilized{Style.RESET_ALL}"
                else:
                    status = f"{Fore.GREEN}Normal{Style.RESET_ALL}"
                
                data.append([cluster.name, cpu_str, mem_str, status])

        except Exception as e:
            if not utils.handle_azure_error(e, "AKS Clusters", f"Subscription: {sub.subscription_id}"):
                break
            continue

    if not data:
        print(f"{Fore.YELLOW}No clusters found.{Style.RESET_ALL}")
    else:
        print(tabulate(data, headers=headers, tablefmt="grid"))
        print(f"\n{Fore.CYAN}Note:{Style.RESET_ALL} Metrics require Container Insights (omsagent) to be enabled.")

if __name__ == "__main__":
    main()
