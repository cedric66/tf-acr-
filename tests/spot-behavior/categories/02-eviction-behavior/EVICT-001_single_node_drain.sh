#!/usr/bin/env bash
# EVICT-001: Single spot node drain reschedules pods to other nodes
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EVICT-001" "Single node drain reschedules pods" "eviction-behavior"
trap cleanup_nodes EXIT

spot_nodes=$(get_spot_nodes)
[[ -z "$spot_nodes" ]] && skip_test "No spot nodes available"
target=$(echo "$spot_nodes" | awk '{print $1}')

# Record pre-drain state
pre_pods=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$target" --no-headers 2>/dev/null | wc -l)
pre_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)
add_evidence "pre_drain" "$(jq -n --argjson pp "$pre_pods" --argjson pt "$pre_total" --arg n "$target" '{node: $n, pods_on_node: $pp, total_running: $pt}')"

assert_gt "Target node has pods" "$pre_pods" 0

drain_node "$target"
sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

post_total=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo 0)
post_on_target=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$target" --no-headers 2>/dev/null | wc -l)

assert_eq "No pods remain on drained node" "$post_on_target" "0"
assert_gte "Total running pods recovered" "$post_total" "$((pre_total - 1))"

add_evidence "post_drain" "$(jq -n --argjson pt "$post_total" --argjson pot "$post_on_target" '{total_running: $pt, pods_on_drained: $pot}')"
finish_test
