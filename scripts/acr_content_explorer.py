#!/usr/bin/env python3
"""
ACR Content Explorer
====================
Explores the content of Azure Container Registries.
Can list repositories in an ACR, or images (tags) within a repository.

Usage:
    python acr_content_explorer.py --registry <acr_name> [--repo <repo_name>] [--subscription <sub_id>] --resource-group <rg_name>
    
    Note: The SDK method to listing repos often requires the registry object or scope. 
    This script assumes you know the ACR Name and Resource Group to get the client context efficiently,
    or it iterates to find it (slower).
"""

import argparse
import sys
from azure.mgmt.containerregistry import ContainerRegistryManagementClient
from tabulate import tabulate
from colorama import init, Fore, Style
import utils

init(autoreset=True)

def list_repositories(client, rg_name, acr_name):
    print(f"Listing repositories for ACR: {acr_name}...")
    try:
        # Note: Management Plane SDK usually lists metadata. 
        # Data Plane (listing tags) often requires a differnet client (ContainerRegistryClient), 
        # but Management SDK can rarely list Repos if 'admin user' is disabled depending on API version.
        # Actually proper way to list content is usually via the Data Plane `azure-containerregistry` library.
        # BUT for this task, I will stick to Management SDK where possible or warn user.
        # Wait, Management SDK `registries` operations don't list content. 
        # We need to use valid approach.
        # For simplicity in this 'DevOps' context, listing Repos is often done via AZ CLI if no data-plane auth is setup.
        # However, let's try to use the raw SDK if possible. 
        # NOTE: azure-mgmt-containerregistry does NOT have data plane usage.
        
        # CORRECTIVE ACTION: As 'azure-containerregistry' (Data Plane) is needed for listing content 
        # and I didn't add it to params, I will use `az acr repository list` wrapper for reliability 
        # OR I will try to use the management client if it exposes anything (it usually doesn't).
        
        # Given the constraints and likely 'admin' or 'AAD' auth needed for data plane, 
        # using a simple subprocess wrapper for `az acr repository` is the robust DevOps way here 
        # without adding complex data-plane auth flows (which often fail with MFA).
        
        import subprocess
        import json
        
        cmd = ["az", "acr", "repository", "list", "--name", acr_name, "--output", "json"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"{Fore.RED}Error listing repos (AZ CLI): {result.stderr}{Style.RESET_ALL}")
            return []
            
        return json.loads(result.stdout)
        
    except Exception as e:
        print(f"{Fore.RED}Failed to list repositories: {e}{Style.RESET_ALL}")
        return []

def list_tags(acr_name, repo_name):
    import subprocess
    import json
    
    print(f"Listing tags for {acr_name}/{repo_name}...")
    # az acr repository show-tags -n <acr> --repository <repo> --detail
    cmd = ["az", "acr", "repository", "show-tags", 
           "--name", acr_name, 
           "--repository", repo_name, 
           "--detail",
           "--orderby", "time_desc",
           "--output", "json"]
           
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"{Fore.RED}Error listing tags: {result.stderr}{Style.RESET_ALL}")
        return []
        
    tags = json.loads(result.stdout)
    # Extract useful summary
    summary = []
    for t in tags[:20]: # Limit to top 20 latest
        summary.append([
            t.get('name'),
            t.get('createdTime'),
            f"{int(t.get('imageSize', 0)) / 1024 / 1024:.2f} MB"
        ])
    return summary

def main():
    parser = argparse.ArgumentParser(description="ACR Content Explorer")
    parser.add_argument("--registry", help="Name of the ACR", required=True)
    parser.add_argument("--repo", help="Filter by specific Repository Name")
    # subscription param is less relevant here as we lean on AZ CLI for data plane, 
    # but kept for consistency if we expanded.
    args = parser.parse_args()

    # NOTE: We are relying on AZ CLI here because 'azure-mgmt-containerregistry' 
    # manages the RESOURCE, not the CONTENT. Listing docker images requires 
    # 'azure-containerregistry' package + Data Plane Auth (Token Exchange), 
    # which is often overkill for a quick admin script. 
    
    if args.repo:
        # List Tags
        tags = list_tags(args.registry, args.repo)
        if tags:
            print(tabulate(tags, headers=["Tag", "Created", "Size"], tablefmt="simple"))
        else:
            print("No tags found.")
    else:
        # List Repos
        repos = list_repositories(None, None, args.registry)
        if repos:
            # Format as a column
            data = [[r] for r in repos]
            print(tabulate(data, headers=["Repositories"], tablefmt="plain"))
        else:
            print("No repositories found.")

if __name__ == "__main__":
    main()
