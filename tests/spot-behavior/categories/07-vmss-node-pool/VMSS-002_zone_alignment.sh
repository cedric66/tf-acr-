#!/usr/bin/env bash
# VMSS-002: Verify VMSS zone alignment matches pool configuration
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "VMSS-002" "VMSS zone alignment matches config" "vmss-node-pool"

LOCATION="${LOCATION:-eastus}"
MC_RG="MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_${LOCATION}"

for pool in "${SPOT_POOLS[@]}"; do
  expected_zones="${POOL_ZONES[$pool]}"

  vmss_json=$(az vmss list -g "$MC_RG" --query "[?tags.\"aks-managed-poolName\"=='$pool']" -o json 2>/dev/null || echo '[]')
  vmss_count=$(echo "$vmss_json" | jq 'length')
  [[ "$vmss_count" -eq 0 ]] && { log_warn "No VMSS for pool $pool"; continue; }

  vmss_name=$(echo "$vmss_json" | jq -r '.[0].name')
  vmss_zones=$(echo "$vmss_json" | jq -r '.[0].zones // [] | sort | join(",")')

  assert_eq "$pool zones match config" "$vmss_zones" "$expected_zones"
done

finish_test
