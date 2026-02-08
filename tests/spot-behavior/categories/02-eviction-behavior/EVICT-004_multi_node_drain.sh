#!/usr/bin/env bash
# EVICT-004: Drain 2 spot nodes from different pools, verify pods reschedule
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EVICT-004" "Multi-node drain from different pools" "eviction-behavior"
trap cleanup_nodes EXIT

# Pick one node from each of two different spot pools
targets=()
used_pools=()
for pool in "${SPOT_POOLS[@]}"; do
  [[ ${#targets[@]} -ge 2 ]] && break
  node=$(kubectl get nodes -l "agentpool=$pool" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  [[ -z "$node" ]] && continue
  targets+=("$node")
  used_pools+=("$pool")
done

[[ ${#targets[@]} -lt 2 ]] && skip_test "Need nodes from at least 2 spot pools"

pre_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)

for t in "${targets[@]}"; do
  drain_node "$t"
done

sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

post_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)

for svc in "${ALL_SERVICES[@]}"; do
  running=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
  assert_gt "$svc has running pods" "$running" 0
done

add_evidence "drain_targets" "$(jq -n --argjson pre "$pre_total" --argjson post "$post_total" \
  '{pre_running: $pre, post_running: $post}')"
finish_test
