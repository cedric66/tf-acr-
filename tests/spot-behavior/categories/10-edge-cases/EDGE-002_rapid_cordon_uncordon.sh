#!/usr/bin/env bash
# EDGE-002: Rapid cordon/uncordon cycling 3 times
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EDGE-002" "Rapid cordon/uncordon cycling" "edge-cases"
trap cleanup_nodes EXIT

target=$(get_spot_nodes | awk '{print $1}')
[[ -z "$target" ]] && skip_test "No spot nodes available"

pre_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)

# Cycle cordon/uncordon 3 times rapidly
for i in 1 2 3; do
  log_step "Cycle $i: cordon"
  cordon_node "$target"
  sleep 3
  log_step "Cycle $i: uncordon"
  uncordon_node "$target"
  sleep 3
done

sleep 10

# Verify node is schedulable and cluster is stable
node_status=$(kubectl get node "$target" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || echo "true")
assert_eq "Node is schedulable after cycling" "$node_status" ""

post_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)
assert_gte "Pod count stable after cycling" "$post_total" "$((pre_total - 1))"

finish_test
