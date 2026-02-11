#!/usr/bin/env bash
# migration-progress.sh - Check spot migration progress
# Usage: ./migration-progress.sh
# Loads configuration from config.sh
# Reference: .env.example and README.md

set -euo pipefail

# Determine script directory to source config.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/config.sh" ]]; then
    source "${SCRIPT_DIR}/config.sh"
else
    echo "Error: config.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

echo "=== Spot Migration Progress for ${CLUSTER_NAME} ==="
echo ""

TOTAL_PODS=0
SPOT_PODS=0
STANDARD_PODS=0

# Get all pods across all non-system namespaces
# We use -o json to avoid multiple kubectl calls in a loop
PODS_JSON=$(kubectl get pods -A -o json)

# Use jq to extract nodeName and then cross-reference with node labels
# To be efficient, we'll get node priorities first
NODE_PRIORITIES=$(kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name) \(.metadata.labels["kubernetes.azure.com/scalesetpriority"] // "standard")"')

# Process pods
while read -r ns name node; do
    if [[ -z "$node" || "$node" == "null" ]]; then continue; fi
    
    # Ignore system namespaces
    if [[ "$ns" =~ ^(kube-|gatekeeper-system|calico-system|azure-arc) ]]; then continue; fi

    TOTAL_PODS=$((TOTAL_PODS + 1))
    
    # Check node priority - use -w for whole word match and handle potential multiple matches
    priority=$(echo "$NODE_PRIORITIES" | grep -w "^$node" | head -n1 | cut -d' ' -f2 || echo "standard")
    
    if [[ "$priority" == "spot" ]]; then
        SPOT_PODS=$((SPOT_PODS + 1))
    else
        STANDARD_PODS=$((STANDARD_PODS + 1))
    fi
done < <(echo "$PODS_JSON" | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.spec.nodeName)"')

if [[ $TOTAL_PODS -gt 0 ]]; then
  SPOT_PCT=$((SPOT_PODS * 100 / TOTAL_PODS))
else
  SPOT_PCT=0
fi

echo "Total user pods:  $TOTAL_PODS"
echo "On spot nodes:    $SPOT_PODS ($SPOT_PCT%)"
echo "On standard:      $STANDARD_PODS"
echo ""

if [[ $SPOT_PCT -ge 70 ]]; then
  echo "✅ Target met (>= 70% on spot)"
elif [[ $SPOT_PCT -ge 50 ]]; then
  echo "⚠️  Progress good but below 70% target"
else
  echo "❌ Below 50% - migration in progress"
fi
