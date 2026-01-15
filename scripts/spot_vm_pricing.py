#!/usr/bin/env python3
"""
Spot VM Pricing & Availability
==============================
Queries Azure Retail Prices API for Spot VM pricing and availability.
Uses Compute Resource SKUs API to check availability in specific regions.

Usage:
    python spot_vm_pricing.py --region eastus [--sku-filter Standard_D]
    python spot_vm_pricing.py --regions-file regions.csv
"""

import argparse
import requests
from azure.mgmt.compute import ComputeManagementClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

RETAIL_PRICES_API = "https://prices.azure.com/api/retail/prices"

def get_spot_prices(region, sku_filter=None):
    """Queries Azure Retail Prices API for Spot VM prices."""
    prices = []
    
    # Build filter
    filter_parts = [
        f"armRegionName eq '{region}'",
        "priceType eq 'Consumption'",
        "contains(skuName, 'Spot')"
    ]
    if sku_filter:
        filter_parts.append(f"contains(armSkuName, '{sku_filter}')")
    
    odata_filter = " and ".join(filter_parts)
    
    try:
        params = {'$filter': odata_filter}
        response = requests.get(RETAIL_PRICES_API, params=params, timeout=30)
        response.raise_for_status()
        
        data = response.json()
        for item in data.get('Items', []):
            if 'Spot' in item.get('skuName', ''):
                prices.append({
                    'sku': item.get('armSkuName', 'Unknown'),
                    'product': item.get('productName', ''),
                    'price_per_hour': item.get('retailPrice', 0),
                    'unit': item.get('unitOfMeasure', ''),
                    'region': region
                })
        
        # Handle pagination
        while data.get('NextPageLink'):
            response = requests.get(data['NextPageLink'], timeout=30)
            response.raise_for_status()
            data = response.json()
            for item in data.get('Items', []):
                if 'Spot' in item.get('skuName', ''):
                    prices.append({
                        'sku': item.get('armSkuName', 'Unknown'),
                        'product': item.get('productName', ''),
                        'price_per_hour': item.get('retailPrice', 0),
                        'unit': item.get('unitOfMeasure', ''),
                        'region': region
                    })
                    
    except Exception as e:
        print(f"{Fore.RED}Error fetching prices: {e}{Style.RESET_ALL}")
    
    return prices

def get_sku_availability(cred, subscription_id, region, sku_filter=None):
    """Checks SKU availability in a region using Compute Resource SKUs API."""
    available = []
    
    try:
        compute_client = ComputeManagementClient(cred, subscription_id)
        skus = compute_client.resource_skus.list(filter=f"location eq '{region}'")
        
        for sku in skus:
            if sku.resource_type != 'virtualMachines':
                continue
            if sku_filter and sku_filter not in sku.name:
                continue
            
            # Check for restrictions
            is_available = True
            restrictions = []
            if sku.restrictions:
                for r in sku.restrictions:
                    if r.type == 'Location':
                        is_available = False
                        restrictions.append('Location')
                    elif r.type == 'Zone':
                        restrictions.append('Zone')
            
            # Get capabilities
            vcpus = '?'
            memory = '?'
            for cap in sku.capabilities or []:
                if cap.name == 'vCPUs':
                    vcpus = cap.value
                elif cap.name == 'MemoryGB':
                    memory = cap.value
            
            available.append({
                'sku': sku.name,
                'vcpus': vcpus,
                'memory_gb': memory,
                'available': is_available,
                'restrictions': ', '.join(restrictions) if restrictions else 'None'
            })
                
    except Exception as e:
        utils.handle_azure_error(e, "Resource SKUs", region)
    
    return available

def main():
    parser = argparse.ArgumentParser(description="Spot VM Pricing & Availability")
    parser.add_argument("--region", help="Azure region to query (e.g., eastus)")
    parser.add_argument("--regions-file", help="CSV file with regions column")
    parser.add_argument("--sku-filter", help="Filter SKUs (e.g., Standard_D)")
    parser.add_argument("--subscription", help="Subscription ID for availability check")
    parser.add_argument("--top", type=int, default=20, help="Show top N cheapest SKUs")
    args = parser.parse_args()
    
    if not args.region and not args.regions_file:
        print(f"{Fore.RED}Error: Specify --region or --regions-file{Style.RESET_ALL}")
        return
    
    regions = [args.region] if args.region else []
    if args.regions_file:
        import csv
        with open(args.regions_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if 'region' in row:
                    regions.append(row['region'])
    
    print(f"\n{Fore.CYAN}Spot VM Pricing Query{Style.RESET_ALL}")
    print(f"{'='*60}\n")
    
    all_prices = []
    for region in regions:
        print(f"Querying prices for {Fore.CYAN}{region}{Style.RESET_ALL}...")
        prices = get_spot_prices(region, args.sku_filter)
        all_prices.extend(prices)
    
    if not all_prices:
        print(f"{Fore.YELLOW}No Spot VMs found for the specified criteria.{Style.RESET_ALL}")
        return
    
    # Sort by price
    all_prices.sort(key=lambda x: x['price_per_hour'])
    
    # Display top N
    data = []
    for p in all_prices[:args.top]:
        price_str = f"${p['price_per_hour']:.4f}/hr"
        monthly = p['price_per_hour'] * 730  # Approximate hours per month
        data.append([
            p['sku'],
            p['region'],
            price_str,
            f"~${monthly:.2f}/mo"
        ])
    
    print(f"\n{Fore.GREEN}Top {args.top} Cheapest Spot VMs:{Style.RESET_ALL}")
    print(tabulate(data, headers=["SKU", "Region", "Spot Price", "Est. Monthly"], tablefmt="grid"))
    
    # Availability check if subscription provided
    if args.subscription and args.region:
        print(f"\n{Fore.CYAN}Checking availability in {args.region}...{Style.RESET_ALL}")
        cred = utils.get_credential()
        availability = get_sku_availability(cred, args.subscription, args.region, args.sku_filter)
        
        if availability:
            avail_data = []
            for a in availability[:15]:
                status = f"{Fore.GREEN}✓{Style.RESET_ALL}" if a['available'] else f"{Fore.RED}✗{Style.RESET_ALL}"
                avail_data.append([a['sku'], a['vcpus'], a['memory_gb'], status, a['restrictions']])
            
            print(tabulate(avail_data, headers=["SKU", "vCPUs", "Memory", "Available", "Restrictions"], tablefmt="simple"))

if __name__ == "__main__":
    main()
