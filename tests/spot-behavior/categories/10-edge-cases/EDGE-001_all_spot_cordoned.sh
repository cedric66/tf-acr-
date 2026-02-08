#!/usr/bin/env bash
# EDGE-001: All spot nodes cordoned - pods go pending, standard scales up
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EDGE-001" "All spot nodes cordoned" "edge-cases"
trap cleanup_nodes EXIT

# Cordon all spot nodes
spot_nodes=$(get_spot_nodes)
[[ -z "$spot_nodes" ]] && skip_test "No spot nodes available"

for node in $spot_nodes; do
  cordon_node "$node"
done

# Drain all spot nodes
for node in $spot_nodes; do
  drain_node "$node"
done

sleep 15

# Check standard pool absorbed the workload
std_count=$(count_ready_nodes_in_pool "$STANDARD_POOL")
assert_gt "Standard pool has nodes" "$std_count" 0

# Wait for pods to reschedule to standard
wait_for_pods_ready "app" 180 || true

# Verify services still running
for svc in "${ALL_SERVICES[@]}"; do
  running=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
  assert_gt "$svc running on fallback" "$running" 0
done

add_evidence "standard_node_count" "$(jq -n --argjson c "$std_count" '{count: $c}')"
finish_test
