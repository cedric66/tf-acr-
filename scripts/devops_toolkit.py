#!/usr/bin/env python3
"""
DevOps Toolkit - Master Controller
==================================
A unified CLI for running AKS/ACR audits and discovery.
Run without arguments for an interactive menu.

Usage:
    python devops_toolkit.py                    # Interactive menu
    python devops_toolkit.py discover           # Run discovery
    python devops_toolkit.py audit security     # Run specific audit
    python devops_toolkit.py spot-pricing --region eastus
"""

import os
import sys
import subprocess
from colorama import init, Fore, Style

init(autoreset=True)

# Script directory
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Available reports/audits organized by category
REPORTS = {
    "1": {
        "name": "Discovery",
        "description": "Scan all subscriptions and generate inventory CSVs",
        "script": "discover.py",
        "category": "discovery"
    },
    "2": {
        "name": "Fleet Overview",
        "description": "High-level inventory of all AKS clusters",
        "script": "aks_fleet_overview.py",
        "category": "inventory"
    },
    "3": {
        "name": "Cost Audit",
        "description": "Analyze node pools for cost optimization",
        "script": "aks_cost_auditor.py",
        "category": "cost"
    },
    "4": {
        "name": "Orphaned Disks",
        "description": "Find unattached managed disks wasting money",
        "script": "aks_disk_auditor.py",
        "category": "cost"
    },
    "5": {
        "name": "Security Audit",
        "description": "RBAC, identity, and policy compliance checks",
        "script": "aks_auth_rbac.py",
        "category": "security"
    },
    "6": {
        "name": "Identity Audit",
        "description": "Check Managed Identity vs Service Principal",
        "script": "aks_identity_audit.py",
        "category": "security"
    },
    "7": {
        "name": "Policy Compliance",
        "description": "Azure Policy compliance state",
        "script": "aks_policy_compliance.py",
        "category": "security"
    },
    "8": {
        "name": "Network Audit",
        "description": "VNet, Subnet, IP usage analysis",
        "script": "aks_network_audit.py",
        "category": "network"
    },
    "9": {
        "name": "Ingress/WAF Audit",
        "description": "AGIC and Web Application Firewall status",
        "script": "aks_ingress_audit.py",
        "category": "network"
    },
    "10": {
        "name": "Upgrade Planner",
        "description": "Compare versions against available upgrades",
        "script": "aks_upgrade_planner.py",
        "category": "lifecycle"
    },
    "11": {
        "name": "Add-on Inventory",
        "description": "Audit enabled add-ons across clusters",
        "script": "aks_addon_inventory.py",
        "category": "lifecycle"
    },
    "12": {
        "name": "Node Utilization",
        "description": "CPU/Memory utilization from Azure Monitor",
        "script": "aks_node_utilization.py",
        "category": "observability"
    },
    "13": {
        "name": "Monitor Insights",
        "description": "Run KQL queries against Log Analytics",
        "script": "aks_monitor_insights.py",
        "category": "observability"
    },
    "14": {
        "name": "Backup Audit",
        "description": "Check Azure Backup for AKS extension",
        "script": "aks_backup_audit.py",
        "category": "dr"
    },
    "15": {
        "name": "Key Vault Integration",
        "description": "Key Vault CSI driver and rotation status",
        "script": "aks_keyvault_integration.py",
        "category": "secrets"
    },
    "16": {
        "name": "ACR Inventory",
        "description": "Azure Container Registry inventory",
        "script": "acr_inventory.py",
        "category": "acr"
    },
    "17": {
        "name": "ACR Content Explorer",
        "description": "List repositories and image tags",
        "script": "acr_content_explorer.py",
        "category": "acr"
    },
    "18": {
        "name": "ACR Vulnerabilities",
        "description": "Defender for Containers findings",
        "script": "acr_vulnerability_report.py",
        "category": "acr"
    },
    "19": {
        "name": "ACR Replication",
        "description": "Geo-replication status for Premium ACRs",
        "script": "acr_replication_audit.py",
        "category": "acr"
    },
    "20": {
        "name": "Spot VM Pricing",
        "description": "Query Spot VM availability and pricing",
        "script": "spot_vm_pricing.py",
        "category": "cost"
    },
    "21": {
        "name": "Quick Security Check (Bash)",
        "description": "Fast CLI-based security sanity checks",
        "script": "aks_security_inspector.sh",
        "category": "security"
    }
}

def print_banner():
    """Prints the toolkit banner."""
    print(f"""
{Fore.CYAN}╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   {Fore.WHITE}AKS DevOps Toolkit{Fore.CYAN}                                    ║
║   {Fore.YELLOW}Comprehensive Azure Kubernetes Audit Suite{Fore.CYAN}             ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝{Style.RESET_ALL}
""")

def print_menu():
    """Prints the interactive menu."""
    categories = {}
    for key, report in REPORTS.items():
        cat = report['category']
        if cat not in categories:
            categories[cat] = []
        categories[cat].append((key, report))
    
    category_names = {
        'discovery': '📊 Discovery',
        'inventory': '📋 Inventory',
        'cost': '💰 Cost & Optimization',
        'security': '🔒 Security & Compliance',
        'network': '🌐 Networking',
        'lifecycle': '🔄 Lifecycle & Upgrades',
        'observability': '📈 Observability',
        'dr': '💾 Disaster Recovery',
        'secrets': '🔑 Secrets Management',
        'acr': '📦 Container Registry'
    }
    
    for cat, items in categories.items():
        print(f"\n{Fore.CYAN}{category_names.get(cat, cat)}{Style.RESET_ALL}")
        for key, report in items:
            print(f"  [{Fore.GREEN}{key:>2}{Style.RESET_ALL}] {report['name']:<25} - {Fore.WHITE}{report['description']}{Style.RESET_ALL}")
    
    print(f"\n  [{Fore.YELLOW} A{Style.RESET_ALL}] Run ALL audits")
    print(f"  [{Fore.YELLOW} Q{Style.RESET_ALL}] Quit")

def run_script(script_name, extra_args=None):
    """Runs a script from the scripts directory."""
    script_path = os.path.join(SCRIPT_DIR, script_name)
    
    if not os.path.exists(script_path):
        print(f"{Fore.RED}Script not found: {script_path}{Style.RESET_ALL}")
        return
    
    cmd = []
    if script_name.endswith('.py'):
        cmd = [sys.executable, script_path]
    elif script_name.endswith('.sh'):
        cmd = ['bash', script_path]
    
    if extra_args:
        cmd.extend(extra_args)
    
    print(f"\n{Fore.CYAN}Running: {script_name}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{'─'*60}{Style.RESET_ALL}\n")
    
    subprocess.run(cmd, cwd=SCRIPT_DIR)
    
    print(f"\n{Fore.CYAN}{'─'*60}{Style.RESET_ALL}")

def get_config_args():
    """Prompts for optional config file."""
    print(f"\n{Fore.YELLOW}Optional: Enter path to config file (or press Enter to skip):{Style.RESET_ALL}")
    config = input("> ").strip()
    if config:
        return ["--config", config]
    return []

def run_all_audits():
    """Runs all audit scripts (excluding discovery and special scripts)."""
    print(f"\n{Fore.CYAN}Running all audits...{Style.RESET_ALL}\n")
    
    skip_scripts = ['discover.py', 'spot_vm_pricing.py', 'acr_content_explorer.py', 'aks_monitor_insights.py']
    
    for key, report in REPORTS.items():
        if report['script'] in skip_scripts:
            continue
        if report['category'] == 'discovery':
            continue
            
        print(f"\n{Fore.GREEN}[{key}] {report['name']}{Style.RESET_ALL}")
        run_script(report['script'])
        
        print(f"\nPress Enter to continue to next report...")
        input()

def interactive_mode():
    """Runs the interactive menu."""
    while True:
        print_banner()
        print_menu()
        
        print(f"\n{Fore.YELLOW}Enter your choice:{Style.RESET_ALL}")
        choice = input("> ").strip().upper()
        
        if choice == 'Q':
            print(f"\n{Fore.CYAN}Goodbye!{Style.RESET_ALL}\n")
            break
        elif choice == 'A':
            run_all_audits()
        elif choice in REPORTS:
            report = REPORTS[choice]
            extra_args = []
            
            # Special handling for certain scripts
            if report['script'] == 'spot_vm_pricing.py':
                print(f"\n{Fore.YELLOW}Enter region (e.g., eastus):{Style.RESET_ALL}")
                region = input("> ").strip()
                if region:
                    extra_args = ["--region", region]
            elif report['script'] == 'acr_content_explorer.py':
                print(f"\n{Fore.YELLOW}Enter ACR name:{Style.RESET_ALL}")
                acr = input("> ").strip()
                if acr:
                    extra_args = ["--registry", acr]
            elif report['script'] == 'aks_monitor_insights.py':
                print(f"\n{Fore.YELLOW}Enter Log Analytics Workspace ID:{Style.RESET_ALL}")
                ws = input("> ").strip()
                if ws:
                    extra_args = ["--workspace", ws]
            else:
                extra_args = get_config_args()
            
            run_script(report['script'], extra_args)
            
            print(f"\n{Fore.YELLOW}Press Enter to return to menu...{Style.RESET_ALL}")
            input()
        else:
            print(f"{Fore.RED}Invalid choice. Please try again.{Style.RESET_ALL}")

def main():
    """Main entry point."""
    if len(sys.argv) > 1:
        # Command-line mode
        cmd = sys.argv[1].lower()
        
        if cmd == 'discover':
            run_script('discover.py', sys.argv[2:])
        elif cmd == 'spot-pricing':
            run_script('spot_vm_pricing.py', sys.argv[2:])
        elif cmd == 'audit':
            if len(sys.argv) > 2:
                audit_type = sys.argv[2].lower()
                if audit_type == 'all':
                    run_all_audits()
                elif audit_type == 'security':
                    for key, report in REPORTS.items():
                        if report['category'] == 'security':
                            run_script(report['script'], sys.argv[3:])
                elif audit_type == 'cost':
                    for key, report in REPORTS.items():
                        if report['category'] == 'cost':
                            run_script(report['script'], sys.argv[3:])
                else:
                    print(f"{Fore.RED}Unknown audit type: {audit_type}{Style.RESET_ALL}")
            else:
                print(f"Usage: {sys.argv[0]} audit [all|security|cost|network|...]")
        elif cmd == 'help' or cmd == '--help':
            print(__doc__)
        else:
            print(f"{Fore.RED}Unknown command: {cmd}{Style.RESET_ALL}")
            print(f"Run without arguments for interactive menu.")
    else:
        # Interactive mode
        interactive_mode()

if __name__ == "__main__":
    main()
