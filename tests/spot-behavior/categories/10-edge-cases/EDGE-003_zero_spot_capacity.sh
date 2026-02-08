#!/usr/bin/env bash
# EDGE-003: Zero spot capacity - 100% fallback to standard, then recovery
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EDGE-003" "Zero spot capacity fallback" "edge-cases"
trap cleanup_nodes EXIT

# Cordon and drain ALL spot nodes
spot_nodes=$(get_spot_nodes)
[[ -z "$spot_nodes" ]] && skip_test "No spot nodes available"

for node in $spot_nodes; do
  cordon_node "$node"
done
for node in $spot_nodes; do
  drain_node "$node"
done

sleep 15
wait_for_pods_ready "app" 180 || true

# Verify ALL user workloads on standard/system
on_spot=0
all_pods=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null)
for node_name in $(echo "$all_pods" | jq -r '.items[].spec.nodeName // empty'); do
  is_spot_node "$node_name" && on_spot=$((on_spot + 1))
done

assert_eq "Zero pods on spot (all cordoned)" "$on_spot" "0"

# Verify services running
for svc in "${ALL_SERVICES[@]}"; do
  running=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
  assert_gt "$svc running during zero-spot" "$running" 0
done

# Uncordon (recovery)
for node in $spot_nodes; do
  uncordon_node "$node"
done

add_evidence_str "spot_nodes_cordoned" "$(echo $spot_nodes | wc -w)"
finish_test
