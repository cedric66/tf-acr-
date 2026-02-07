#!/usr/bin/env bash
# EDGE-005: Pods stay pending when standard pool is at capacity after spot drain
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EDGE-005" "Resource pressure on standard pool" "edge-cases"
trap cleanup_nodes EXIT

# Record standard pool capacity
std_nodes=$(count_ready_nodes_in_pool "$STANDARD_POOL")
assert_gt "Standard pool has nodes" "$std_nodes" 0

# Drain a spot node to push load to standard
target=$(get_spot_nodes | awk '{print $1}')
[[ -z "$target" ]] && skip_test "No spot nodes available"

pre_pods_on_target=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$target" --no-headers 2>/dev/null | wc -l)
drain_node "$target"
sleep 15

# Check standard pool utilization increased
std_pods=0
for node in $(kubectl get nodes -l "agentpool=$STANDARD_POOL" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  count=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$node" --no-headers 2>/dev/null | wc -l)
  std_pods=$((std_pods + count))
done

# Check for pending pods (may indicate pressure)
pending=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Pending || echo 0)

add_evidence "standard_pressure" "$(jq -n \
  --argjson std_nodes "$std_nodes" \
  --argjson std_pods "$std_pods" \
  --argjson pending "$pending" \
  --argjson displaced "$pre_pods_on_target" \
  '{standard_nodes: $std_nodes, standard_pods: $std_pods, pending_pods: $pending, displaced: $displaced}')"

# If no pending pods, standard absorbed; if pending, autoscaler will scale up
if [[ "$pending" -gt 0 ]]; then
  log_step "Pending pods detected - autoscaler should scale standard pool"
  # Wait for autoscaler to handle
  wait_for_pods_ready "app" 180 || true
fi

# Final check - all services should eventually be running
for svc in "${ALL_SERVICES[@]}"; do
  running=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
  assert_gt "$svc running after pressure test" "$running" 0
done

finish_test
