#!/usr/bin/env bash
# DIST-007: Verify pods are distributed across multiple spot pools
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DIST-007" "Pods distributed across multiple spot pools" "pod-distribution"

pools_with_pods=()
pool_pod_counts='{}'

for pool in "${SPOT_POOLS[@]}"; do
  node_count=$(count_ready_nodes_in_pool "$pool")
  if [[ "$node_count" -eq 0 ]]; then
    continue
  fi

  pool_pods=0
  for node in $(kubectl get nodes -l "agentpool=$pool" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    pods_on_node=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$node" --no-headers 2>/dev/null | wc -l || echo 0)
    pool_pods=$((pool_pods + pods_on_node))
  done

  if [[ "$pool_pods" -gt 0 ]]; then
    pools_with_pods+=("$pool")
  fi
  pool_pod_counts=$(echo "$pool_pod_counts" | jq --arg p "$pool" --argjson c "$pool_pods" '. + {($p): $c}')
done

active_pools=${#pools_with_pods[@]}
assert_gte "At least 2 spot pools have pods" "$active_pools" 2
add_evidence "pool_pod_distribution" "$pool_pod_counts"
finish_test
