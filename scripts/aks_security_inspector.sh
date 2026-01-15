#!/bin/bash

# AKS Security Inspector using Azure CLI
# ======================================
# Requires: az cli, jq

set -e

echo "Starting AKS Security Inspection..."

# Check requirements
if ! command -v az &> /dev/null; then
    echo "Error: 'az' command not found. Please install Azure CLI."
    exit 1
fi

echo "Fetching list of all AKS clusters..."

# Get all clusters with key security properties
# Using JMESPath to project relevant fields
CLUSTERS=$(az aks list --query "[].{
    name: name, 
    rg: resourceGroup, 
    private: apiServerAccessProfile.enablePrivateCluster, 
    rbac: enableRbac, 
    networkPolicy: networkProfile.networkPolicy,
    azurePolicy: addonProfiles.azurepolicy.enabled,
    monitor: addonProfiles.omsagent.enabled
}" -o json)

echo ""
echo "----------------------------------------------------------------"
echo "Security Report"
echo "----------------------------------------------------------------"

# 1. Public API Access Check
echo " [!] Checking for Public API Access..."
echo "$CLUSTERS" | jq -r '.[] | select(.private == null or .private == false) | "     \u001b[31m[PUBLIC]\u001b[0m " + .name + " (RG: " + .rg + ")"' || echo "No public clusters found."

# 2. RBAC Check
echo ""
echo " [!] Checking for Disabled RBAC..."
echo "$CLUSTERS" | jq -r '.[] | select(.rbac == false) | "     \u001b[31m[NO-RBAC]\u001b[0m " + .name + " (RG: " + .rg + ")"' 

# 3. Network Policy Check
echo ""
echo " [!] Checking for Missing Network Policy..."
echo "$CLUSTERS" | jq -r '.[] | select(.networkPolicy == null or .networkPolicy == "null") | "     \u001b[33m[NO-NET-POL]\u001b[0m " + .name + " (RG: " + .rg + ")"'

# 4. Azure Policy Addon
echo ""
echo " [!] Checking for Azure Policy Add-on..."
echo "$CLUSTERS" | jq -r '.[] | select(.azurePolicy == null or .azurePolicy == false) | "     \u001b[33m[NO-POLICY]\u001b[0m " + .name + " (RG: " + .rg + ")"'

echo ""
echo "----------------------------------------------------------------"
echo "Inspection Complete."
