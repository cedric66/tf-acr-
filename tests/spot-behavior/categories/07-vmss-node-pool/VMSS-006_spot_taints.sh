#!/usr/bin/env bash
# VMSS-006: Verify spot nodes have NoSchedule taint
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "VMSS-006" "Spot nodes have NoSchedule taint" "vmss-node-pool"

spot_nodes=$(kubectl get nodes -l "kubernetes.azure.com/scalesetpriority=spot" -o json 2>/dev/null)
spot_count=$(echo "$spot_nodes" | jq '.items | length')
assert_gt "At least 1 spot node exists" "$spot_count" 0

tainted_count=0
untainted=()

for node_name in $(echo "$spot_nodes" | jq -r '.items[].metadata.name'); do
  has_taint=$(kubectl get node "$node_name" -o json | jq '
    [.spec.taints[]? |
     select(.key == "kubernetes.azure.com/scalesetpriority" and .value == "spot" and .effect == "NoSchedule")
    ] | length')

  if [[ "$has_taint" -gt 0 ]]; then
    tainted_count=$((tainted_count + 1))
  else
    untainted+=("$node_name")
  fi
done

assert_eq "All spot nodes tainted" "$tainted_count" "$spot_count"

if [[ ${#untainted[@]} -gt 0 ]]; then
  add_evidence_str "untainted_spot_nodes" "$(printf '%s,' "${untainted[@]}")"
fi

finish_test
