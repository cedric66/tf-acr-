"""
Shared utilities for AKS DevOps Scripts.
"""
import sys
import json
import os
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import SubscriptionClient
from colorama import Fore, Style
from azure.core.exceptions import HttpResponseError, ClientAuthenticationError

def handle_azure_error(e, resource_type="resource", context=""):
    """
    Handles common Azure SDK exceptions with user-friendly messages.
    Returns True if the error was handled (script should continue), False if fatal.
    """
    error_msg = str(e)
    
    # Authentication Errors
    if isinstance(e, ClientAuthenticationError):
        print(f"{Fore.RED}[AUTH ERROR]{Style.RESET_ALL} Failed to authenticate.")
        print(f"  → Run 'az login' or check your Service Principal credentials.")
        return False
    
    # HTTP Response Errors (most common)
    if isinstance(e, HttpResponseError):
        status = e.status_code
        
        if status == 401:
            print(f"{Fore.RED}[AUTH ERROR]{Style.RESET_ALL} Unauthorized (401) accessing {resource_type}.")
            print(f"  → Your credentials may have expired. Run 'az login'.")
            return False
        
        if status == 403:
            print(f"{Fore.YELLOW}[PERMISSION DENIED]{Style.RESET_ALL} Cannot access {resource_type}. {context}")
            print(f"  → You lack the required RBAC role. Contact your Azure Admin.")
            return True  # Non-fatal, skip this resource
        
        if status == 404:
            print(f"{Fore.YELLOW}[NOT FOUND]{Style.RESET_ALL} {resource_type} not found. {context}")
            return True  # Non-fatal
        
        if status == 429:
            print(f"{Fore.YELLOW}[THROTTLED]{Style.RESET_ALL} Too many requests. Try again later.")
            return True
        
        # Generic HTTP error
        print(f"{Fore.RED}[API ERROR]{Style.RESET_ALL} HTTP {status} while accessing {resource_type}.")
        print(f"  → {error_msg[:200]}")
        return True
    
    # Catch-all for other exceptions
    print(f"{Fore.RED}[ERROR]{Style.RESET_ALL} Unexpected error accessing {resource_type}: {error_msg[:200]}")
    return True

def get_credential():
    """Returns the DefaultAzureCredential."""
    try:
        return DefaultAzureCredential()
    except Exception as e:
        print(f"{Fore.RED}Failed to authenticate: {e}{Style.RESET_ALL}")
        sys.exit(1)

def load_config(config_path):
    """Loads target configuration from a JSON file."""
    if not os.path.exists(config_path):
        print(f"{Fore.RED}Config file not found: {config_path}{Style.RESET_ALL}")
        sys.exit(1)
    
    with open(config_path, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            print(f"{Fore.RED}Invalid JSON in config file: {e}{Style.RESET_ALL}")
            sys.exit(1)

def get_target_subscriptions(credential, config=None, specific_sub_id=None):
    """
    Returns a list of subscription objects to scan. 
    If config is provided, uses it to determine scope (supports specific subs).
    If specific_sub_id is provided, overrides everything else.
    Otherwise, lists all accessible subscriptions.
    """
    sub_client = SubscriptionClient(credential)
    all_subs = []
    
    # 1. Specific CLI Override
    if specific_sub_id:
        return [type('obj', (object,), {'subscription_id': specific_sub_id, 'display_name': 'CLI Override'})]

    # 2. Config File Strategy
    if config and 'targets' in config:
        target_subs = set(t.get('subscription_id') for t in config['targets'] if t.get('subscription_id'))
        if target_subs:
            # We return dummy objects with the ID so existing loop logic works
            # Ideally we would validate they exist, but for speed we assume valid ID
            return [type('obj', (object,), {'subscription_id': s, 'display_name': 'Configured Sub'}) for s in target_subs]

    # 3. Default: List All
    try:
        print(f"{Fore.CYAN}Listing all subscriptions...{Style.RESET_ALL}")
        return list(sub_client.subscriptions.list())
    except Exception as e:
        print(f"{Fore.RED}Error listing subscriptions: {e}{Style.RESET_ALL}")
        return []

def should_process_resource_group(rg_name, sub_id, config=None):
    """
    Determines if a Resource Group should be processed based on the config.
    Returns True if no config or if RG matches config allow-list.
    """
    if not config or 'targets' not in config:
        return True
    
    for target in config['targets']:
        if target.get('subscription_id') == sub_id:
            # If resource_groups list is present, check it
            if 'resource_groups' in target:
                return rg_name in target['resource_groups']
            # If clusters list is present, we might be filtering at cluster level, 
            # but usually we need to list the RG to find the cluster. 
            # For simplicity, we allow the RG if specific clusters are named, 
            # and let the cluster filter handle the specific check.
            return True
            
    return False

def should_process_cluster(cluster_name, sub_id, config=None):
    """
    Determines if a cluster name matches the config filter.
    """
    if not config or 'targets' not in config:
        return True

    for target in config['targets']:
        if target.get('subscription_id') == sub_id:
            if 'clusters' in target:
                return cluster_name in target['clusters']
    
    return True
