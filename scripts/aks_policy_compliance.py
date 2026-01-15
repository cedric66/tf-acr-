#!/usr/bin/env python3
"""
AKS Policy Compliance
=====================
Queries Azure Policy compliance state for AKS clusters.

Usage:
    python aks_policy_compliance.py [--config config.json] [--subscription sub_id]
"""

import argparse
from azure.mgmt.containerservice import ContainerServiceClient
from azure.mgmt.policyinsights import PolicyInsightsClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def get_policy_compliance(policy_client, cluster_id):
    """Gets policy compliance summary for a specific cluster scope."""
    try:
        # Query policy states for the cluster resource
        query = policy_client.policy_states.list_query_results_for_resource(
            policy_states_resource="latest",
            resource_id=cluster_id
        )
        
        compliant = 0
        non_compliant = 0
        non_compliant_policies = []
        
        for state in query:
            if state.compliance_state == "Compliant":
                compliant += 1
            elif state.compliance_state == "NonCompliant":
                non_compliant += 1
                policy_name = state.policy_definition_name or state.policy_assignment_name or "Unknown"
                if policy_name not in non_compliant_policies:
                    non_compliant_policies.append(policy_name)
        
        return compliant, non_compliant, non_compliant_policies
        
    except Exception as e:
        utils.handle_azure_error(e, "Policy Compliance", cluster_id.split('/')[-1])
        return 0, 0, []

def compliance_status(compliant, non_compliant):
    """Returns a formatted compliance status."""
    if non_compliant == 0 and compliant == 0:
        return f"{Fore.YELLOW}No Policies{Style.RESET_ALL}"
    elif non_compliant == 0:
        return f"{Fore.GREEN}Compliant ({compliant}){Style.RESET_ALL}"
    else:
        return f"{Fore.RED}Non-Compliant ({non_compliant}/{compliant + non_compliant}){Style.RESET_ALL}"

def main():
    parser = argparse.ArgumentParser(description="AKS Policy Compliance")
    parser.add_argument("--config", help="Path to JSON config file")
    parser.add_argument("--subscription", help="Specific subscription ID")
    args = parser.parse_args()

    cred = utils.get_credential()
    config = utils.load_config(args.config) if args.config else None
    subs = utils.get_target_subscriptions(cred, config, args.subscription)

    data = []
    headers = ["Cluster", "Status", "Non-Compliant Policies"]

    for sub in subs:
        try:
            aks_client = ContainerServiceClient(cred, sub.subscription_id)
            policy_client = PolicyInsightsClient(cred, sub.subscription_id)
            
            clusters = list(aks_client.managed_clusters.list())
            
            for cluster in clusters:
                rg_name = cluster.id.split('/')[4]
                if not utils.should_process_resource_group(rg_name, sub.subscription_id, config):
                    continue
                if not utils.should_process_cluster(cluster.name, sub.subscription_id, config):
                    continue

                compliant, non_compliant, nc_policies = get_policy_compliance(policy_client, cluster.id)
                
                status = compliance_status(compliant, non_compliant)
                policies_str = ", ".join(nc_policies[:3]) if nc_policies else "-"
                if len(nc_policies) > 3:
                    policies_str += f" (+{len(nc_policies) - 3} more)"
                
                data.append([cluster.name, status, policies_str])

        except Exception as e:
            if not utils.handle_azure_error(e, "AKS Clusters", f"Subscription: {sub.subscription_id}"):
                break
            continue

    if not data:
        print(f"{Fore.YELLOW}No clusters found.{Style.RESET_ALL}")
    else:
        print(tabulate(data, headers=headers, tablefmt="grid"))
        print(f"\n{Fore.CYAN}Note:{Style.RESET_ALL} Ensure Azure Policy add-on is enabled for in-cluster enforcement.")

if __name__ == "__main__":
    main()
