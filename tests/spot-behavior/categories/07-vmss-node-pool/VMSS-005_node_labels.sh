#!/usr/bin/env bash
# VMSS-005: Verify node labels match pool type (spot/standard/system)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "VMSS-005" "Node labels match pool type" "vmss-node-pool"

# Check spot pool nodes
for pool in "${SPOT_POOLS[@]}"; do
  nodes=$(kubectl get nodes -l "agentpool=$pool" -o json 2>/dev/null)
  count=$(echo "$nodes" | jq '.items | length')
  [[ "$count" -eq 0 ]] && continue

  first_node=$(echo "$nodes" | jq '.items[0]')
  labels=$(echo "$first_node" | jq '.metadata.labels')

  workload_type=$(echo "$labels" | jq -r '.["workload-type"] // "missing"')
  priority_label=$(echo "$labels" | jq -r '.priority // "missing"')
  azure_priority=$(echo "$labels" | jq -r '.["kubernetes.azure.com/scalesetpriority"] // "missing"')

  assert_eq "$pool workload-type=spot" "$workload_type" "spot"
  assert_eq "$pool priority=spot" "$priority_label" "spot"
  assert_eq "$pool azure priority=spot" "$azure_priority" "spot"
done

# Check standard pool nodes
std_nodes=$(kubectl get nodes -l "agentpool=$STANDARD_POOL" -o json 2>/dev/null)
std_count=$(echo "$std_nodes" | jq '.items | length')
if [[ "$std_count" -gt 0 ]]; then
  first_std=$(echo "$std_nodes" | jq '.items[0].metadata.labels')
  wt=$(echo "$first_std" | jq -r '.["workload-type"] // "missing"')
  pr=$(echo "$first_std" | jq -r '.priority // "missing"')
  assert_eq "stdworkload workload-type=standard" "$wt" "standard"
  assert_eq "stdworkload priority=on-demand" "$pr" "on-demand"
fi

# Check system pool nodes
sys_nodes=$(kubectl get nodes -l "agentpool=$SYSTEM_POOL" -o json 2>/dev/null)
sys_count=$(echo "$sys_nodes" | jq '.items | length')
if [[ "$sys_count" -gt 0 ]]; then
  first_sys=$(echo "$sys_nodes" | jq '.items[0].metadata.labels')
  npt=$(echo "$first_sys" | jq -r '.["node-pool-type"] // "missing"')
  assert_eq "system node-pool-type=system" "$npt" "system"
fi

finish_test
