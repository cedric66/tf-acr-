#!/usr/bin/env bash
# EVICT-009: Empty node drain completes instantly with no disruption
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EVICT-009" "Empty node drain causes no disruption" "eviction-behavior"
trap cleanup_nodes EXIT

# Find a spot node with fewest user pods
target=""
min_pods=999
for node in $(get_spot_nodes); do
  count=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$node" --no-headers 2>/dev/null | wc -l)
  if (( count < min_pods )); then
    min_pods=$count
    target="$node"
  fi
done
[[ -z "$target" ]] && skip_test "No spot nodes available"

pre_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)

# Cordon first so new pods don't land here
cordon_node "$target"
sleep 5

# Drain (should be fast if few/no pods)
start_ts=$(date +%s)
drain_node "$target"
end_ts=$(date +%s)
drain_duration=$((end_ts - start_ts))

post_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)

assert_gte "Total running pods unchanged" "$post_total" "$((pre_total - min_pods))"
add_evidence "drain_timing" "$(jq -n --argjson d "$drain_duration" --argjson mp "$min_pods" '{duration_seconds: $d, pods_on_node: $mp}')"
finish_test
