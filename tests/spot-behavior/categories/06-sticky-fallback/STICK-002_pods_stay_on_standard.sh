#!/usr/bin/env bash
# STICK-002: Pods stay on standard after fallback (sticky behavior)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "STICK-002" "Pods stay on standard (sticky fallback)" "sticky-fallback"
trap cleanup_nodes EXIT

# Drain a spot pool
target_pool=""
for pool in "${SPOT_POOLS[@]}"; do
  count=$(count_ready_nodes_in_pool "$pool")
  if [[ "$count" -gt 0 ]]; then
    target_pool="$pool"
    break
  fi
done
[[ -z "$target_pool" ]] && skip_test "No spot pool with nodes"

for node in $(kubectl get nodes -l "agentpool=$target_pool" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  drain_node "$node"
done

sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

# Count pods on standard now
std_pods_t0=0
for node in $(kubectl get nodes -l "agentpool=$STANDARD_POOL" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  count=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$node" --no-headers 2>/dev/null | wc -l)
  std_pods_t0=$((std_pods_t0 + count))
done

# Wait 60 seconds - pods should NOT auto-migrate back
log_step "Waiting 60s to verify sticky behavior..."
sleep 60

# Uncordon the drained nodes (simulating spot capacity recovery)
for node in $(kubectl get nodes -l "agentpool=$target_pool" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  uncordon_node "$node"
done

sleep 10

# Pods should still be on standard (sticky)
std_pods_t1=0
for node in $(kubectl get nodes -l "agentpool=$STANDARD_POOL" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  count=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$node" --no-headers 2>/dev/null | wc -l)
  std_pods_t1=$((std_pods_t1 + count))
done

assert_gte "Pods still on standard after recovery (sticky)" "$std_pods_t1" "$std_pods_t0"

add_evidence "sticky" "$(jq -n --argjson t0 "$std_pods_t0" --argjson t1 "$std_pods_t1" \
  '{standard_pods_after_drain: $t0, standard_pods_after_60s: $t1}')"
finish_test
