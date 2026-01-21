#!/usr/bin/env bash
#
# add-spot-pools.sh - Generate commands to add Spot node pools to AKS
#
# Usage:
#   ./add-spot-pools.sh --resource-group <RG> --name <CLUSTER> [--execute]
#   ./add-spot-pools.sh --mock <mock-file.json>   # For testing
#

set -euo pipefail

# ==================== Configuration ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/spot-config.yaml"

# ==================== Argument Parsing ====================
RESOURCE_GROUP=""
CLUSTER_NAME=""
MOCK_FILE=""
EXECUTE=false

usage() {
    echo "Usage: $0 --resource-group <RG> --name <CLUSTER> [--execute] [--mock <file>]"
    echo "  --execute    Actually run the commands (default: dry-run, print only)"
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
        --execute)
            EXECUTE=true
            shift
            ;;
        *)
            usage
            ;;
    esac
done

# ==================== Helper Functions ====================

parse_yaml_value() {
    local file=$1
    local key=$2
    # Extract value and strip inline comments
    grep -E "^  ${key}:" "$file" | head -1 | sed "s/^  ${key}: *//" | sed 's/#.*//' | tr -d "'" | xargs
}

parse_yaml_list() {
    local file=$1
    local key=$2
    grep -A 100 "^${key}:" "$file" | grep -E "^  - " | sed 's/^  - //' | head -10
}

get_cluster_json() {
    if [[ -n "$MOCK_FILE" ]]; then
        cat "$MOCK_FILE"
    else
        az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" -o json
    fi
}

get_available_skus() {
    local region=$1
    if [[ -n "$MOCK_FILE" ]]; then
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

select_best_sku() {
    local skus_json=$1
    local preferred_skus=$2
    
    for sku in $preferred_skus; do
        local is_available
        is_available=$(echo "$skus_json" | jq -r --arg name "$sku" '
            [.[] | select(.name == $name and (.restrictions | length == 0))] | length
        ')
        if [[ "$is_available" -gt 0 ]]; then
            echo "$sku"
            return
        fi
    done
    echo ""
}

# ==================== Main Logic ====================

echo "=============== ADD SPOT POOLS ==============="

# 1. Get cluster info
CLUSTER_JSON=$(get_cluster_json)
LOCATION=$(echo "$CLUSTER_JSON" | jq -r '.location')
CLUSTER_NAME_DISPLAY=$(echo "$CLUSTER_JSON" | jq -r '.name')

# 2. Read config
EVICTION_POLICY=$(parse_yaml_value "$CONFIG_FILE" "eviction_policy")
SPOT_MAX_PRICE=$(parse_yaml_value "$CONFIG_FILE" "spot_max_price")
MIN_COUNT=$(parse_yaml_value "$CONFIG_FILE" "min_count")
MAX_COUNT=$(parse_yaml_value "$CONFIG_FILE" "max_count")
OS_TYPE=$(parse_yaml_value "$CONFIG_FILE" "os_type")
PREFERRED_SKUS=$(parse_yaml_list "$CONFIG_FILE" "preferred_skus")

# 3. Select SKU
AVAILABLE_SKUS_JSON=$(get_available_skus "$LOCATION")
SELECTED_SKU=$(select_best_sku "$AVAILABLE_SKUS_JSON" "$PREFERRED_SKUS")

if [[ -z "$SELECTED_SKU" ]]; then
    echo "ERROR: No preferred SKUs available in $LOCATION"
    exit 1
fi

echo "Cluster: $CLUSTER_NAME_DISPLAY | Region: $LOCATION"
echo "Selected SKU: $SELECTED_SKU"
echo ""

# 4. Check existing Spot pools
if [[ -n "$MOCK_FILE" ]]; then
    NODE_POOLS=$(echo "$CLUSTER_JSON" | jq -r '.agentPoolProfiles')
else
    NODE_POOLS=$(az aks nodepool list --resource-group "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" -o json)
fi

EXISTING_SPOT_POOLS=$(echo "$NODE_POOLS" | jq -r '[.[] | select(.scaleSetPriority == "Spot")] | .[].name' 2>/dev/null || echo "")
if [[ -z "$EXISTING_SPOT_POOLS" ]]; then
    SPOT_COUNT=0
else
    SPOT_COUNT=$(echo "$EXISTING_SPOT_POOLS" | wc -l)
fi

echo "Existing Spot pools: $SPOT_COUNT"

# 5. Determine how many pools to add
POOLS_NEEDED=$((2 - SPOT_COUNT))
if [[ $POOLS_NEEDED -le 0 ]]; then
    echo "✓ Already have 2+ Spot pools. No action needed."
    exit 0
fi

echo "Pools to add: $POOLS_NEEDED"
echo ""
echo "============ GENERATED COMMANDS ============"

# 6. Generate commands
COMMANDS=()
for i in $(seq 1 $POOLS_NEEDED); do
    POOL_NAME="spot$(date +%s | tail -c 5)${i}"
    
    CMD="az aks nodepool add \
  --resource-group ${RESOURCE_GROUP:-\$RESOURCE_GROUP} \
  --cluster-name ${CLUSTER_NAME_DISPLAY} \
  --name ${POOL_NAME} \
  --priority Spot \
  --eviction-policy ${EVICTION_POLICY} \
  --spot-max-price ${SPOT_MAX_PRICE} \
  --node-vm-size ${SELECTED_SKU} \
  --enable-cluster-autoscaler \
  --min-count ${MIN_COUNT} \
  --max-count ${MAX_COUNT} \
  --os-type ${OS_TYPE} \
  --node-taints kubernetes.azure.com/scalesetpriority=spot:NoSchedule \
  --labels kubernetes.azure.com/scalesetpriority=spot"
    
    echo "$CMD"
    echo ""
    COMMANDS+=("$CMD")
done

# 7. Execute if requested
if $EXECUTE; then
    echo ""
    echo "============ EXECUTING ============"
    for cmd in "${COMMANDS[@]}"; do
        echo "Running: $cmd"
        eval "$cmd"
    done
else
    echo "============================================"
    echo "DRY RUN: Commands not executed."
    echo "Add --execute flag to run these commands."
    echo "============================================"
fi
