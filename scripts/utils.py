"""
Shared utilities for AKS DevOps Scripts.

This module provides:
- Azure authentication helpers
- Configuration loading and filtering
- Standardized error handling with retry logic
- Output formatting utilities
"""
from __future__ import annotations

import sys
import json
import os
import time
import functools
from dataclasses import dataclass
from typing import Any, Callable, Optional, TypeVar, List, Dict

from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import SubscriptionClient
from colorama import Fore, Style, init
from azure.core.exceptions import HttpResponseError, ClientAuthenticationError

init(autoreset=True)

# Type variable for generic retry decorator
T = TypeVar('T')

# Global output format flag
_output_format: str = "table"


@dataclass
class SubscriptionInfo:
    """Represents an Azure subscription."""
    subscription_id: str
    display_name: str = "Unknown"


def set_output_format(fmt: str) -> None:
    """Sets the global output format ('table' or 'json')."""
    global _output_format
    _output_format = fmt


def get_output_format() -> str:
    """Gets the current output format."""
    return _output_format


def is_json_output() -> bool:
    """Returns True if JSON output is enabled."""
    return _output_format == "json"


def output_results(data: List[Dict[str, Any]], headers: List[str] = None) -> None:
    """
    Outputs results in the configured format (table or JSON).
    
    Args:
        data: List of dictionaries containing the data
        headers: Optional list of column headers (for table format)
    """
    if is_json_output():
        print(json.dumps(data, indent=2, default=str))
    else:
        from tabulate import tabulate
        if data:
            if headers:
                # Convert dicts to lists matching header order
                rows = [[row.get(h, '') for h in headers] for row in data]
                print(tabulate(rows, headers=headers, tablefmt="grid"))
            else:
                print(tabulate(data, headers="keys", tablefmt="grid"))
        else:
            print(f"{Fore.YELLOW}No results found.{Style.RESET_ALL}")


def retry_on_throttle(
    max_retries: int = 3,
    base_delay: float = 2.0,
    max_delay: float = 60.0
) -> Callable[[Callable[..., T]], Callable[..., T]]:
    """
    Decorator that retries a function on HTTP 429 (throttling) errors.
    
    Uses exponential backoff with jitter.
    
    Args:
        max_retries: Maximum number of retry attempts
        base_delay: Initial delay in seconds
        max_delay: Maximum delay between retries
    
    Example:
        @retry_on_throttle(max_retries=3)
        def call_azure_api():
            return client.some_operation()
    """
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @functools.wraps(func)
        def wrapper(*args, **kwargs) -> T:
            last_exception = None
            
            for attempt in range(max_retries + 1):
                try:
                    return func(*args, **kwargs)
                except HttpResponseError as e:
                    if e.status_code == 429:
                        last_exception = e
                        if attempt < max_retries:
                            # Exponential backoff: 2, 4, 8, ... seconds
                            delay = min(base_delay * (2 ** attempt), max_delay)
                            # Add jitter (0-25% of delay)
                            import random
                            delay += random.uniform(0, delay * 0.25)
                            
                            if not is_json_output():
                                print(f"{Fore.YELLOW}[THROTTLED]{Style.RESET_ALL} "
                                      f"Rate limited. Retrying in {delay:.1f}s... "
                                      f"(attempt {attempt + 1}/{max_retries})")
                            time.sleep(delay)
                        else:
                            raise
                    else:
                        raise
            
            # Should not reach here, but just in case
            if last_exception:
                raise last_exception
            
        return wrapper
    return decorator


def handle_azure_error(
    e: Exception,
    resource_type: str = "resource",
    context: str = ""
) -> bool:
    """
    Handles common Azure SDK exceptions with user-friendly messages.
    
    Args:
        e: The exception to handle
        resource_type: Description of the resource being accessed
        context: Additional context for the error message
    
    Returns:
        True if the error was handled (script should continue), False if fatal.
    """
    # Skip output in JSON mode - errors will be in structured format
    if is_json_output():
        return True
    
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


def get_credential() -> DefaultAzureCredential:
    """Returns the DefaultAzureCredential for Azure authentication."""
    try:
        return DefaultAzureCredential()
    except Exception as e:
        if not is_json_output():
            print(f"{Fore.RED}Failed to authenticate: {e}{Style.RESET_ALL}")
        sys.exit(1)


def load_config(config_path: str) -> Optional[Dict[str, Any]]:
    """
    Loads target configuration from a JSON file.
    
    Args:
        config_path: Path to the JSON configuration file
    
    Returns:
        Parsed configuration dictionary or None on error
    """
    if not os.path.exists(config_path):
        if not is_json_output():
            print(f"{Fore.RED}Config file not found: {config_path}{Style.RESET_ALL}")
        sys.exit(1)
    
    with open(config_path, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            if not is_json_output():
                print(f"{Fore.RED}Invalid JSON in config file: {e}{Style.RESET_ALL}")
            sys.exit(1)


def get_target_subscriptions(
    credential: DefaultAzureCredential,
    config: Optional[Dict[str, Any]] = None,
    specific_sub_id: Optional[str] = None
) -> List[SubscriptionInfo]:
    """
    Returns a list of subscription objects to scan.
    
    Priority:
    1. specific_sub_id (CLI override)
    2. config file targets
    3. All accessible subscriptions
    
    Args:
        credential: Azure credential for authentication
        config: Optional configuration dictionary
        specific_sub_id: Optional specific subscription ID to target
    
    Returns:
        List of SubscriptionInfo objects
    """
    # 1. Specific CLI Override
    if specific_sub_id:
        return [SubscriptionInfo(subscription_id=specific_sub_id, display_name='CLI Override')]

    # 2. Config File Strategy
    if config and 'targets' in config:
        target_subs = set(t.get('subscription_id') for t in config['targets'] if t.get('subscription_id'))
        if target_subs:
            return [SubscriptionInfo(subscription_id=s, display_name='Configured') for s in target_subs]

    # 3. Default: List All
    try:
        if not is_json_output():
            print(f"{Fore.CYAN}Listing all subscriptions...{Style.RESET_ALL}")
        
        sub_client = SubscriptionClient(credential)
        subs = list(sub_client.subscriptions.list())
        
        return [
            SubscriptionInfo(
                subscription_id=s.subscription_id,
                display_name=s.display_name or "Unknown"
            )
            for s in subs
        ]
    except Exception as e:
        if not is_json_output():
            print(f"{Fore.RED}Error listing subscriptions: {e}{Style.RESET_ALL}")
        return []


def should_process_resource_group(
    rg_name: str,
    sub_id: str,
    config: Optional[Dict[str, Any]] = None
) -> bool:
    """
    Determines if a Resource Group should be processed based on the config.
    
    Args:
        rg_name: Name of the resource group
        sub_id: Subscription ID containing the resource group
        config: Optional configuration dictionary
    
    Returns:
        True if the resource group should be processed
    """
    if not config or 'targets' not in config:
        return True
    
    for target in config['targets']:
        if target.get('subscription_id') == sub_id:
            if 'resource_groups' in target:
                return rg_name in target['resource_groups']
            return True
            
    return False


def should_process_cluster(
    cluster_name: str,
    sub_id: str,
    config: Optional[Dict[str, Any]] = None
) -> bool:
    """
    Determines if a cluster name matches the config filter.
    
    Args:
        cluster_name: Name of the AKS cluster
        sub_id: Subscription ID containing the cluster
        config: Optional configuration dictionary
    
    Returns:
        True if the cluster should be processed
    """
    if not config or 'targets' not in config:
        return True

    for target in config['targets']:
        if target.get('subscription_id') == sub_id:
            if 'clusters' in target:
                return cluster_name in target['clusters']
    
    return True


def add_common_args(parser) -> None:
    """
    Adds common CLI arguments to an argparse parser.
    
    Adds:
    - --config: Path to JSON config file
    - --subscription: Specific subscription ID
    - --output: Output format (table or json)
    """
    parser.add_argument("--config", help="Path to JSON config file for filtering")
    parser.add_argument("--subscription", help="Specific subscription ID to target")
    parser.add_argument(
        "--output", "-o",
        choices=["table", "json"],
        default="table",
        help="Output format: 'table' (default) or 'json'"
    )


def init_from_args(args) -> None:
    """
    Initializes utils settings from parsed CLI arguments.
    
    Call this after parsing args to set up output format.
    """
    if hasattr(args, 'output') and args.output:
        set_output_format(args.output)
