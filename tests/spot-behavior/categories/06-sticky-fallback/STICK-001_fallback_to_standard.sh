#!/usr/bin/env bash
# STICK-001: Pods fall back to standard pool when spot drained
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "STICK-001" "Fallback to standard pool" "sticky-fallback"
trap cleanup_nodes EXIT

# Pick a spot pool and drain all its nodes
target_pool=""
for pool in "${SPOT_POOLS[@]}"; do
  count=$(count_ready_nodes_in_pool "$pool")
  if [[ "$count" -gt 0 ]]; then
    target_pool="$pool"
    break
  fi
done
[[ -z "$target_pool" ]] && skip_test "No spot pool with nodes"

# Drain all nodes in the target pool
for node in $(kubectl get nodes -l "agentpool=$target_pool" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  drain_node "$node"
done

sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

# Check that some pods landed on standard pool
std_pods=0
for node in $(kubectl get nodes -l "agentpool=$STANDARD_POOL" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  count=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$node" --no-headers 2>/dev/null | wc -l)
  std_pods=$((std_pods + count))
done

assert_gt "Pods on standard pool after spot drain" "$std_pods" 0

add_evidence "fallback" "$(jq -n --arg p "$target_pool" --argjson sp "$std_pods" '{drained_pool: $p, pods_on_standard: $sp}')"
finish_test
