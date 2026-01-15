#!/usr/bin/env python3
"""
AKS Monitor Insights
====================
Runs KQL queries against Log Analytics Workspaces.
Requires the 'azure-monitor-query' package.

Usage:
    python aks_monitor_insights.py --workspace <workspace_id>
"""

import argparse
import datetime
from azure.monitor.query import LogsQueryClient, LogsQueryStatus
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

# Pre-defined queries for DevOps Architects
QUERIES = {
    "Node CPU Top 5": """
        Perf
        | where ObjectName == "K8SNode" and CounterName == "cpuUsageNanoCores"
        | summarize AvgCPU = avg(CounterValue) by Computer
        | top 5 by AvgCPU desc
    """,
    "Container Restarts (24h)": """
        KubePodInventory
        | where TimeGenerated > ago(24h)
        | summarize Restarts = sum(ContainerRestartCount) by ContainerName, Namespace
        | where Restarts > 0
        | top 10 by Restarts desc
    """,
    "Cluster Autoscaler Events": """
        KubeEvents
        | where TimeGenerated > ago(24h)
        | where Reason == "ScaleDown" or Reason == "ScaleUp"
        | project TimeGenerated, Message, Reason
        | top 20 by TimeGenerated desc
    """
}

def run_query(client, workspace_id, query_name, kql):
    print(f"\n{Fore.CYAN}--- {query_name} ---{Style.RESET_ALL}")
    try:
        # Time range: Last 24 hours
        end_time = datetime.datetime.now(datetime.timezone.utc)
        start_time = end_time - datetime.timedelta(days=1)
        
        response = client.query_workspace(
            workspace_id=workspace_id,
            query=kql,
            timespan=(start_time, end_time)
        )

        if response.status == LogsQueryStatus.SUCCESS:
            data = [row for row in response.tables[0].rows]
            columns = response.tables[0].columns
            if data:
                print(tabulate(data, headers=columns, tablefmt="simple"))
            else:
                print("No results found.")
        else:
            print(f"{Fore.RED}Query Failed.{Style.RESET_ALL}")

    except Exception as e:
        print(f"{Fore.RED}Error executing query: {e}{Style.RESET_ALL}")

def main():
    parser = argparse.ArgumentParser(description="AKS Monitor Insights")
    parser.add_argument("--workspace", help="Log Analytics Workspace ID", required=True)
    args = parser.parse_args()

    cred = utils.get_credential()
    client = LogsQueryClient(cred)

    print(f"Querying Workspace: {args.workspace}")

    for name, kql in QUERIES.items():
        run_query(client, args.workspace, name, kql)

if __name__ == "__main__":
    main()
