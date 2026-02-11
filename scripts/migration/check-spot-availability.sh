#!/usr/bin/env bash
# check-spot-availability.sh - Validate SKU availability in target region
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

echo "=== Spot SKU Availability Check for ${LOCATION} ==="
echo ""

ALL_AVAILABLE=true

for pool in spotmemory1 spotmemory2 spotgeneral1 spotgeneral2 spotcompute; do
  var_name="POOL_VM_SIZE_${pool}"
  SKU="${!var_name}"

  # Check for restrictions
  RESTRICTIONS=$(az vm list-skus --location "$LOCATION" --resource-type virtualMachines \
    --query "[?name=='${SKU}'].restrictions | [0]" -o json 2>/dev/null || echo '[]')

  if [[ "$RESTRICTIONS" == "[]" || "$RESTRICTIONS" == "null" ]]; then
    echo "  ✅ ${pool}: ${SKU} - Available"
  else
    echo "  ❌ ${pool}: ${SKU} - Restricted"
    REASON=$(echo "$RESTRICTIONS" | jq -r '.[].reasonCode' 2>/dev/null || echo 'Unknown')
    echo "     Restrictions: ${REASON:-None found}"
    ALL_AVAILABLE=false
  fi
done

echo ""
if [[ "$ALL_AVAILABLE" == "true" ]]; then
  echo "✅ All configured SKUs are available in ${LOCATION}"
  exit 0
else
  echo "❌ Some SKUs are restricted. Update config.sh with alternative SKUs."
  echo ""
  echo "Available alternatives in ${LOCATION}:"
  az vm list-skus --location "$LOCATION" --resource-type virtualMachines \
    --query "[?contains(name, 's_v5') || contains(name, 's_v2')].name" -o tsv | \
    grep -E '^[^ ]+$' | sort -u | head -20
  exit 1
fi
