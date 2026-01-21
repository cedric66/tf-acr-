#!/usr/bin/env bash
#
# eligibility-report.sh - Check AKS cluster eligibility for Spot optimization
#
# Usage:
#   ./eligibility-report.sh --resource-group <RG> --name <CLUSTER>
#   ./eligibility-report.sh --mock <mock-file.json>   # For testing
#

set -euo pipefail

# ==================== Configuration ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/spot-config.yaml"

# ==================== Argument Parsing ====================
RESOURCE_GROUP=""
CLUSTER_NAME=""
MOCK_FILE=""

usage() {
    echo "Usage: $0 --resource-group <RG> --name <CLUSTER> [--mock <file>]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group|-g)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --name|-n)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --mock)
            MOCK_FILE="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

# ==================== Helper Functions ====================

# Parse YAML config (simple key extraction - works for flat YAML)
parse_yaml_list() {
    local file=$1
    local key=$2
    grep -A 100 "^${key}:" "$file" | grep -E "^  - " | sed 's/^  - //' | head -10
}

# Get cluster JSON (from Azure or mock)
get_cluster_json() {
    if [[ -n "$MOCK_FILE" ]]; then
        cat "$MOCK_FILE"
    else
        az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" -o json
    fi
}

# Get available SKUs in region
get_available_skus() {
    local region=$1
    if [[ -n "$MOCK_FILE" ]]; then
        # Mock mode: look for skus.json in same directory
        local mock_dir
        mock_dir=$(dirname "$MOCK_FILE")
        if [[ -f "${mock_dir}/skus.json" ]]; then
            cat "${mock_dir}/skus.json"
        else
            echo "[]"
        fi
    else
        az vm list-skus --location "$region" --resource-type virtualMachines -o json
    fi
}

# Check if SKU supports Spot
sku_supports_spot() {
    local sku_json=$1
    local sku_name=$2
    echo "$sku_json" | jq -r --arg name "$sku_name" '
        .[] | select(.name == $name) |
        .capabilities[] | select(.name == "LowPriorityCapable") | .value
    ' 2>/dev/null || echo "False"
}

# Check if SKU is restricted
sku_is_restricted() {
    local sku_json=$1
    local sku_name=$2
    local restrictions
    restrictions=$(echo "$sku_json" | jq -r --arg name "$sku_name" '
        .[] | select(.name == $name) | .restrictions | length
    ' 2>/dev/null || echo "0")
    [[ "$restrictions" -gt 0 ]]
}

# ==================== Main Logic ====================

echo "================== AKS SPOT ELIGIBILITY REPORT =================="
echo ""

# 1. Get cluster info
CLUSTER_JSON=$(get_cluster_json)
CLUSTER_NAME_DISPLAY=$(echo "$CLUSTER_JSON" | jq -r '.name')
LOCATION=$(echo "$CLUSTER_JSON" | jq -r '.location')
SKU_TIER=$(echo "$CLUSTER_JSON" | jq -r '.sku.tier // "Free"')

echo "Cluster: $CLUSTER_NAME_DISPLAY | Region: $LOCATION | Tier: $SKU_TIER"
echo "----------------------------------------------------------------"

# 2. Check Network Compatibility for NAP
NETWORK_PLUGIN=$(echo "$CLUSTER_JSON" | jq -r '.networkProfile.networkPlugin // "unknown"')
NETWORK_MODE=$(echo "$CLUSTER_JSON" | jq -r '.networkProfile.networkMode // "unknown"')
NETWORK_DATAPLANE=$(echo "$CLUSTER_JSON" | jq -r '.networkProfile.networkDataplane // "unknown"')

NAP_COMPATIBLE=false
NAP_REASON=""

if [[ "$NETWORK_DATAPLANE" == "cilium" ]]; then
    NAP_COMPATIBLE=true
    NAP_REASON="Cilium dataplane detected"
elif [[ "$NETWORK_PLUGIN" == "azure" && "$NETWORK_MODE" == "overlay" ]]; then
    NAP_COMPATIBLE=true
    NAP_REASON="Azure CNI Overlay detected"
elif [[ "$NETWORK_PLUGIN" == "azure" ]]; then
    NAP_COMPATIBLE=false
    NAP_REASON="Azure CNI (non-overlay) - NAP requires overlay or Cilium"
elif [[ "$NETWORK_PLUGIN" == "kubenet" ]]; then
    NAP_COMPATIBLE=false
    NAP_REASON="Kubenet - NAP requires Azure CNI Overlay or Cilium"
else
    NAP_COMPATIBLE=false
    NAP_REASON="Unknown network configuration"
fi

if $NAP_COMPATIBLE; then
    echo "[✓] Network: $NETWORK_PLUGIN + $NETWORK_MODE → NAP COMPATIBLE ($NAP_REASON)"
else
    echo "[✗] Network: $NETWORK_PLUGIN + $NETWORK_MODE → NAP INCOMPATIBLE"
    echo "    Reason: $NAP_REASON"
    echo "    Fallback: Will use Cluster Autoscaler with manual Spot pools"
fi

# 3. Check SKU Availability
echo ""
echo "Checking SKU availability for Spot..."

AVAILABLE_SKUS_JSON=$(get_available_skus "$LOCATION")
PREFERRED_SKUS=$(parse_yaml_list "$CONFIG_FILE" "preferred_skus")

SELECTED_SKU=""
for sku in $PREFERRED_SKUS; do
    SPOT_CAPABLE=$(sku_supports_spot "$AVAILABLE_SKUS_JSON" "$sku")
    if [[ "$SPOT_CAPABLE" == "True" ]]; then
        if ! sku_is_restricted "$AVAILABLE_SKUS_JSON" "$sku"; then
            SELECTED_SKU="$sku"
            echo "[✓] SKU Available: $sku (Spot capable, no restrictions)"
            break
        else
            echo "[!] SKU Restricted: $sku (trying next...)"
        fi
    else
        echo "[!] SKU Not Spot-Capable: $sku (trying next...)"
    fi
done

if [[ -z "$SELECTED_SKU" ]]; then
    echo "[✗] CRITICAL: No preferred SKUs available for Spot in $LOCATION"
    echo "    Please update preferred_skus in spot-config.yaml"
    exit 1
fi

# 4. Check Existing Node Pools
echo ""
echo "Analyzing existing node pools..."

if [[ -n "$MOCK_FILE" ]]; then
    # Mock mode: node pools embedded in cluster JSON
    NODE_POOLS=$(echo "$CLUSTER_JSON" | jq -r '.agentPoolProfiles')
else
    NODE_POOLS=$(az aks nodepool list --resource-group "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" -o json)
fi

SPOT_POOL_COUNT=$(echo "$NODE_POOLS" | jq '[.[] | select(.scaleSetPriority == "Spot")] | length')
SYSTEM_POOL_COUNT=$(echo "$NODE_POOLS" | jq '[.[] | select(.mode == "System")] | length')
TOTAL_POOLS=$(echo "$NODE_POOLS" | jq 'length')

echo "  Total pools: $TOTAL_POOLS | System pools: $SYSTEM_POOL_COUNT | Spot pools: $SPOT_POOL_COUNT"

if [[ "$SPOT_POOL_COUNT" -eq 0 ]]; then
    echo "[!] Gap: No Spot pools found. Recommend adding 2 for HA."
elif [[ "$SPOT_POOL_COUNT" -eq 1 ]]; then
    echo "[!] Warning: Only 1 Spot pool. Recommend adding 1 more for resilience."
else
    echo "[✓] Spot pools: $SPOT_POOL_COUNT (OK)"
fi

# 5. Check Cost Analysis
COST_ANALYSIS_ENABLED=$(echo "$CLUSTER_JSON" | jq -r '.azureMonitorProfile.costAnalysis.enabled // false')
if [[ "$COST_ANALYSIS_ENABLED" == "true" ]]; then
    echo "[✓] Cost Analysis: Enabled"
else
    echo "[!] Cost Analysis: DISABLED. Recommend enabling for visibility."
fi

# 6. Summary
echo ""
echo "================================================================"
echo "RECOMMENDATION:"
if $NAP_COMPATIBLE; then
    echo "  → Enable Node Autoprovisioning (NAP) for automatic Spot scaling"
    echo "  Command: az aks update -g $RESOURCE_GROUP -n $CLUSTER_NAME_DISPLAY --node-provisioning-mode Auto"
else
    echo "  → Add manual Spot pools with Cluster Autoscaler"
    echo "  Run: ./add-spot-pools.sh --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME_DISPLAY"
fi
echo "  Selected SKU: $SELECTED_SKU"
echo "================================================================"
