import os
import sys
import json
from azure.identity import DefaultAzureCredential, ClientSecretCredential
from azure.core.exceptions import ClientAuthenticationError, HttpResponseError
from colorama import Fore, Style

def get_credential():
    """Gets Azure credentials."""
    try:
        return DefaultAzureCredential()
    except Exception as e:
        print(f"{Fore.RED}Failed to load credentials: {e}{Style.RESET_ALL}")
        sys.exit(1)

def load_config(config_path):
    """Loads JSON config file."""
    if not os.path.exists(config_path):
        print(f"{Fore.RED}Config file not found: {config_path}{Style.RESET_ALL}")
        return None
    try:
        with open(config_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"{Fore.RED}Invalid JSON config: {e}{Style.RESET_ALL}")
        return None

def get_target_subscriptions(cred, config=None, specific_sub_id=None):
    """Returns a list of subscription objects to target."""
    from azure.mgmt.resource import SubscriptionClient
    sub_client = SubscriptionClient(cred)
    try:
        all_subs = list(sub_client.subscriptions.list())
    except Exception as e:
        handle_azure_error(e, "Subscriptions")
        sys.exit(1)

    targets = []
    
    if specific_sub_id:
        targets = [s for s in all_subs if s.subscription_id == specific_sub_id]
        if not targets:
            print(f"{Fore.RED}Subscription {specific_sub_id} not found.{Style.RESET_ALL}")
            sys.exit(1)
        return targets

    if config and 'targets' in config:
        target_ids = [t['subscription_id'] for t in config['targets']]
        targets = [s for s in all_subs if s.subscription_id in target_ids]
    else:
        targets = all_subs

    if not targets:
        print(f"{Fore.YELLOW}No accessible subscriptions found.{Style.RESET_ALL}")
        sys.exit(1)
        
    return targets

def should_process_resource_group(rg_name, sub_id, config):
    """Checks if a resource group should be processed based on config."""
    if not config or 'targets' not in config:
        return True
    
    for target in config['targets']:
        if target['subscription_id'] == sub_id:
            if 'resource_groups' in target and target['resource_groups']:
                return rg_name in target['resource_groups']
            return True
    return False

def should_process_cluster(cluster_name, sub_id, config):
    """Checks if a cluster should be processed based on config."""
    if not config or 'targets' not in config:
        return True
        
    for target in config['targets']:
        if target['subscription_id'] == sub_id:
            if 'clusters' in target and target['clusters']:
                return cluster_name in target['clusters']
            return True
    return False

def handle_azure_error(e, resource_type="resource", context=""):
    """
    Handles common Azure SDK exceptions with user-friendly messages.
    Returns True if the error was handled (script should continue), False if fatal.
    """
    error_msg = str(e)
    
    if isinstance(e, ClientAuthenticationError):
        print(f"{Fore.RED}[AUTH ERROR]{Style.RESET_ALL} Failed to authenticate.")
        print(f"  → Run 'az login' or check your Service Principal credentials.")
        return False
    
    if isinstance(e, HttpResponseError):
        status = e.status_code
        
        if status == 401:
            print(f"{Fore.RED}[AUTH ERROR]{Style.RESET_ALL} Unauthorized (401) accessing {resource_type}.")
            print(f"  → Your credentials may have expired. Run 'az login'.")
            return False
        
        if status == 403:
            print(f"{Fore.YELLOW}[PERMISSION DENIED]{Style.RESET_ALL} Cannot access {resource_type}. {context}")
            print(f"  → You lack the required RBAC role. Contact your Azure Admin.")
            return True
        
        if status == 404:
            print(f"{Fore.YELLOW}[NOT FOUND]{Style.RESET_ALL} {resource_type} not found. {context}")
            return True
        
        if status == 429:
            print(f"{Fore.YELLOW}[THROTTLED]{Style.RESET_ALL} Too many requests. Try again later.")
            return True
        
        print(f"{Fore.RED}[API ERROR]{Style.RESET_ALL} HTTP {status} while accessing {resource_type}.")
        print(f"  → {error_msg[:200]}")
        return True
    
    print(f"{Fore.RED}[ERROR]{Style.RESET_ALL} Unexpected error accessing {resource_type}: {error_msg[:200]}")
    return True
