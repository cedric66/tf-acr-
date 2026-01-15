#!/usr/bin/env python3
"""
AKS Cost Auditor Script
=======================
Inspects AKS node pools to identify potential cost savings and optimization opportunities.
Looks for low-utilization pools, opportunities for Spot instances, and expensive OS SKUs.

Usage:
    python aks_cost_auditor.py [--subscription <sub_id>] [--output json]

Examples:
    # Interactive table output
    python aks_cost_auditor.py

    # JSON output for automation/reporting
    python aks_cost_auditor.py --output json > cost_report.json
"""
from __future__ import annotations

import argparse
from typing import List, Dict, Any

from azure.mgmt.containerservice import ContainerServiceClient
from tabulate import tabulate
from colorama import init, Fore, Style

import utils

init(autoreset=True)


def audit_cluster(cluster) -> List[Dict[str, Any]]:
    """
    Audits a cluster's node pools for cost optimization opportunities.
    
    Returns a list of findings, one per node pool.
    """
    findings = []
    
    if not cluster.agent_pool_profiles:
        return []

    for pool in cluster.agent_pool_profiles:
        scale_set_priority = pool.scale_set_priority or "Regular"
        
        finding = {
            "cluster_name": cluster.name,
            "pool_name": pool.name,
            "mode": pool.mode,
            "vm_size": pool.vm_size,
            "node_count": pool.count,
            "priority": scale_set_priority,
            "autoscaling": pool.enable_auto_scaling or False,
            "os_type": pool.os_type,
            "recommendations": []
        }
        
        # Check: User pool with fixed high count - consider Spot
        if pool.mode == "User" and scale_set_priority == "Regular" and pool.count > 2:
            finding["recommendations"].append("Consider Spot VMs for non-critical workloads")

        # Check: System pool sizing
        if pool.mode == "System" and pool.count > 3:
            finding["recommendations"].append("High System node count - review sizing")

        # Check: Windows License Cost
        if pool.os_type == "Windows":
            finding["recommendations"].append("Windows licensing adds cost")

        # Check: Auto-scaling disabled
        if not pool.enable_auto_scaling and pool.mode == "User" and pool.count > 0:
            finding["recommendations"].append("Enable autoscaler for demand-based scaling")

        findings.append(finding)

    return findings


def format_for_table(finding: Dict[str, Any]) -> List[str]:
    """Formats a finding for table display with colors."""
    spot_status = f"{Fore.GREEN}SPOT{Style.RESET_ALL}" if finding['priority'] == "Spot" else "Regular"
    autoscaling = "Enabled" if finding['autoscaling'] else f"{Fore.YELLOW}Fixed{Style.RESET_ALL}"
    recommendations = "; ".join(finding['recommendations']) if finding['recommendations'] else ""
    
    if finding['recommendations']:
        recommendations = f"{Fore.YELLOW}{recommendations}{Style.RESET_ALL}"
    
    return [
        finding['cluster_name'],
        finding['pool_name'],
        finding['mode'],
        finding['vm_size'],
        finding['node_count'],
        spot_status,
        autoscaling,
        recommendations[:50] + "..." if len(recommendations) > 50 else recommendations
    ]


@utils.retry_on_throttle(max_retries=3)
def list_clusters(client: ContainerServiceClient):
    """Lists all managed clusters with retry on throttling."""
    return list(client.managed_clusters.list())


def main():
    parser = argparse.ArgumentParser(description="AKS Cost Auditor")
    utils.add_common_args(parser)
    args = parser.parse_args()
    
    utils.init_from_args(args)

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subscriptions = utils.get_target_subscriptions(cred, config, args.subscription)

    all_findings: List[Dict[str, Any]] = []
    headers = ["Cluster", "Pool", "Mode", "SKU", "Count", "Priority", "Scaling", "Notes"]

    for sub in subscriptions:
        try:
            aks_client = ContainerServiceClient(cred, sub.subscription_id)
            clusters = list_clusters(aks_client)
            
            for cluster in clusters:
                rg_name = cluster.id.split('/')[4]
                if not utils.should_process_resource_group(rg_name, sub.subscription_id, config):
                    continue
                if not utils.should_process_cluster(cluster.name, sub.subscription_id, config):
                    continue

                findings = audit_cluster(cluster)
                for f in findings:
                    f['subscription_id'] = sub.subscription_id
                all_findings.extend(findings)

        except Exception as e:
            utils.handle_azure_error(e, "AKS Clusters", f"Subscription: {sub.subscription_id}")
            continue

    # Output results
    if utils.is_json_output():
        # Include summary stats in JSON
        output = {
            "total_pools": len(all_findings),
            "pools_with_recommendations": sum(1 for f in all_findings if f['recommendations']),
            "spot_pools": sum(1 for f in all_findings if f['priority'] == 'Spot'),
            "findings": all_findings
        }
        utils.output_results([output])  # Wrap in list for consistency
    else:
        if not all_findings:
            print(f"\n{Fore.GREEN}No obvious cost anomalies found (or no clusters reachable).{Style.RESET_ALL}")
        else:
            table_data = [format_for_table(f) for f in all_findings]
            print("\n" + tabulate(table_data, headers=headers, tablefmt="grid"))
            
            # Summary
            pools_with_recs = sum(1 for f in all_findings if f['recommendations'])
            spot_pools = sum(1 for f in all_findings if f['priority'] == 'Spot')
            print(f"\n{Fore.CYAN}Summary:{Style.RESET_ALL}")
            print(f"  • Total node pools: {len(all_findings)}")
            print(f"  • Pools using Spot: {spot_pools}")
            print(f"  • Pools with recommendations: {pools_with_recs}")


if __name__ == "__main__":
    main()
