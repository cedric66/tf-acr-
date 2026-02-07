#!/usr/bin/env bash
# VMSS-004: Verify VMSS autoscale min/max matches node pool config
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "VMSS-004" "VMSS autoscale ranges match config" "vmss-node-pool"

# Expected ranges from variables.tf
declare -A POOL_MIN=([system]=3 [stdworkload]=2 [spotgeneral1]=0 [spotmemory1]=0 [spotgeneral2]=0 [spotcompute]=0 [spotmemory2]=0)
declare -A POOL_MAX=([system]=6 [stdworkload]=10 [spotgeneral1]=20 [spotmemory1]=15 [spotgeneral2]=15 [spotcompute]=10 [spotmemory2]=10)

# Check via AKS node pool API
pool_info=$(az aks nodepool list --cluster-name "$CLUSTER_NAME" -g "$RESOURCE_GROUP" -o json 2>/dev/null || echo '[]')

for pool in "$SYSTEM_POOL" "$STANDARD_POOL" "${SPOT_POOLS[@]}"; do
  pool_data=$(echo "$pool_info" | jq --arg p "$pool" '[.[] | select(.name == $p)] | .[0] // empty')
  [[ -z "$pool_data" || "$pool_data" == "null" ]] && { log_warn "Pool $pool not found"; continue; }

  actual_min=$(echo "$pool_data" | jq '.minCount // 0')
  actual_max=$(echo "$pool_data" | jq '.maxCount // 0')
  expected_min="${POOL_MIN[$pool]}"
  expected_max="${POOL_MAX[$pool]}"

  assert_eq "$pool min count" "$actual_min" "$expected_min"
  assert_eq "$pool max count" "$actual_max" "$expected_max"

  # Verify autoscaling is enabled
  autoscale=$(echo "$pool_data" | jq -r '.enableAutoScaling // false')
  assert_eq "$pool autoscaling enabled" "$autoscale" "true"
done

finish_test
