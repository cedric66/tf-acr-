#!/usr/bin/env bash
# VMSS-001: Verify VMSS spot configuration (priority, eviction policy, max price)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "VMSS-001" "VMSS spot pool configuration" "vmss-node-pool"

LOCATION="${LOCATION:-eastus}"
MC_RG="MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_${LOCATION}"

for pool in "${SPOT_POOLS[@]}"; do
  vmss_json=$(az vmss list -g "$MC_RG" --query "[?tags.\"aks-managed-poolName\"=='$pool']" -o json 2>/dev/null || echo '[]')
  vmss_count=$(echo "$vmss_json" | jq 'length')

  if [[ "$vmss_count" -eq 0 ]]; then
    log_warn "No VMSS found for pool $pool"
    continue
  fi

  vmss_name=$(echo "$vmss_json" | jq -r '.[0].name')
  vmss_detail=$(az vmss show -n "$vmss_name" -g "$MC_RG" -o json 2>/dev/null)

  priority=$(echo "$vmss_detail" | jq -r '.virtualMachineProfile.priority // "unknown"')
  eviction=$(echo "$vmss_detail" | jq -r '.virtualMachineProfile.evictionPolicy // "unknown"')
  max_price=$(echo "$vmss_detail" | jq -r '.virtualMachineProfile.billingProfile.maxPrice // "unknown"')

  assert_eq "$pool priority is Spot" "$priority" "Spot"
  assert_eq "$pool eviction policy is Delete" "$eviction" "Delete"
  assert_eq "$pool max price is -1" "$max_price" "-1"
done

finish_test
