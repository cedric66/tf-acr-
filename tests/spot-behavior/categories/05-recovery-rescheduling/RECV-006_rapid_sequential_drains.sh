#!/usr/bin/env bash
# RECV-006: Rapid sequential drains - 2 nodes drained 30s apart
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "RECV-006" "Rapid sequential drains" "recovery-rescheduling"
trap cleanup_nodes EXIT

# Pick 2 spot nodes from different pools
targets=()
for pool in "${SPOT_POOLS[@]}"; do
  [[ ${#targets[@]} -ge 2 ]] && break
  node=$(kubectl get nodes -l "agentpool=$pool" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  [[ -n "$node" ]] && targets+=("$node")
done
[[ ${#targets[@]} -lt 2 ]] && skip_test "Need 2 spot nodes from different pools"

pre_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)

# Drain first node
drain_node "${targets[0]}"

# Wait 30s then drain second
sleep 30
drain_node "${targets[1]}"

# Wait for full recovery
sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

post_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)

for svc in "${ALL_SERVICES[@]}"; do
  running=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
  assert_gt "$svc recovered after sequential drains" "$running" 0
done

add_evidence "sequential_drain" "$(jq -n --argjson pre "$pre_total" --argjson post "$post_total" \
  '{pre_running: $pre, post_running: $post}')"
finish_test
