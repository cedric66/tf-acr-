#!/usr/bin/env bash
# VMSS-003: Verify VMSS VM SKU matches pool configuration
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "VMSS-003" "VMSS VM SKU matches pool config" "vmss-node-pool"

LOCATION="${LOCATION:-eastus}"
MC_RG="MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_${LOCATION}"

all_pools=("${SPOT_POOLS[@]}" "$STANDARD_POOL" "$SYSTEM_POOL")

for pool in "${all_pools[@]}"; do
  expected_sku="${POOL_VM_SIZE[$pool]}"

  vmss_json=$(az vmss list -g "$MC_RG" --query "[?tags.\"aks-managed-poolName\"=='$pool']" -o json 2>/dev/null || echo '[]')
  vmss_count=$(echo "$vmss_json" | jq 'length')
  [[ "$vmss_count" -eq 0 ]] && { log_warn "No VMSS for pool $pool"; continue; }

  actual_sku=$(echo "$vmss_json" | jq -r '.[0].sku.name')
  assert_eq "$pool VM SKU matches" "$actual_sku" "$expected_sku"
done

finish_test
