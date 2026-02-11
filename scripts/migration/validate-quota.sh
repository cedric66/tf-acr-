#!/usr/bin/env bash
# validate-quota.sh - Check if quota supports your pool sizing
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

echo "=== Quota Validation for ${LOCATION} ==="
echo ""

TOTAL_SPOT_VCPUS=0

for pool in spotmemory1 spotmemory2 spotgeneral1 spotgeneral2 spotcompute; do
  sku_var="POOL_VM_SIZE_${pool}"
  max_var="POOL_MAX_${pool}"
  SKU="${!sku_var}"
  MAX="${!max_var}"
  
  # Get vCPUs for SKU
  VCPUS=$(az vm list-skus --location "$LOCATION" --resource-type virtualMachines \
    --query "[?name=='${SKU}'].capabilities[?name=='vCPUs'].value | [0]" -o tsv 2>/dev/null || echo "")
  
  if [[ -n "$VCPUS" && "$VCPUS" =~ ^[0-9]+$ ]]; then
    POOL_VCPUS=$((MAX * VCPUS))
    TOTAL_SPOT_VCPUS=$((TOTAL_SPOT_VCPUS + POOL_VCPUS))
    echo "  ${pool} (${SKU}): ${MAX} nodes * ${VCPUS} vCPUs = ${POOL_VCPUS}"
  else
    echo "  ⚠️ Could not determine valid vCPUs for ${SKU} (found: '${VCPUS:-empty}')"
  fi
done

echo ""
echo "Total max spot vCPUs needed: $TOTAL_SPOT_VCPUS"

# Fetch current regional quota
# Note: Using localizedValue for 'Total Regional vCPUs' or value 'cores'
QUOTA_DATA=$(az vm list-usage --location "$LOCATION" --query "[?name.value=='cores' || contains(name.localizedValue, 'Total Regional')]" -o json 2>/dev/null || echo "[]")

if [[ "$QUOTA_DATA" == "[]" || -z "$QUOTA_DATA" ]]; then
  echo "⚠️ Could not fetch quota data for ${LOCATION}. Skipping headroom check."
  exit 0
fi

CURRENT_QUOTA=$(echo "$QUOTA_DATA" | jq -r '.[0].limit // 0')
CURRENT_USAGE=$(echo "$QUOTA_DATA" | jq -r '.[0].currentValue // 0')
AVAILABLE_QUOTA=$((CURRENT_QUOTA - CURRENT_USAGE))

echo "Current Regional vCPU Limit: $CURRENT_QUOTA"
echo "Current Usage:               $CURRENT_USAGE"
echo "Available Headroom:          $AVAILABLE_QUOTA"
echo ""

if [[ "$TOTAL_SPOT_VCPUS" -gt "$AVAILABLE_QUOTA" ]]; then
  echo "❌ INSUFFICIENT QUOTA - Request increase of at least $((TOTAL_SPOT_VCPUS - AVAILABLE_QUOTA)) vCPUs"
  exit 1
else
  echo "✅ Sufficient quota available"
fi
