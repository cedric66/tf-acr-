#!/usr/bin/env bash
# EVICT-010: Drain 1 node from each of 3 spot pools simultaneously
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EVICT-010" "Simultaneous multi-pool drain" "eviction-behavior"
trap cleanup_nodes EXIT

targets=()
pools_used=()
for pool in "${SPOT_POOLS[@]}"; do
  [[ ${#targets[@]} -ge 3 ]] && break
  node=$(kubectl get nodes -l "agentpool=$pool" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  [[ -z "$node" ]] && continue
  targets+=("$node")
  pools_used+=("$pool")
done

[[ ${#targets[@]} -lt 3 ]] && skip_test "Need nodes from at least 3 spot pools"

pre_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)

# Drain all 3 in background
pids=()
for t in "${targets[@]}"; do
  drain_node "$t" &
  pids+=($!)
done

# Wait for all drains to complete
for pid in "${pids[@]}"; do
  wait "$pid" || true
done

sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

# Verify all services recovered
for svc in "${ALL_SERVICES[@]}"; do
  running=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
  assert_gt "$svc running after 3-pool drain" "$running" 0
done

post_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)
add_evidence "simultaneous_drain" "$(jq -n --argjson pre "$pre_total" --argjson post "$post_total" \
  --argjson count "${#targets[@]}" '{pre_running: $pre, post_running: $post, nodes_drained: $count}')"
finish_test
