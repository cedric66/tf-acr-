#!/usr/bin/env bash
# RECV-001: Measure pod reschedule time after spot node drain
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "RECV-001" "Pod reschedule time measurement" "recovery-rescheduling"
trap cleanup_nodes EXIT

target=$(get_spot_nodes | awk '{print $1}')
[[ -z "$target" ]] && skip_test "No spot nodes available"

pre_pods=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$target" --no-headers 2>/dev/null | wc -l)
assert_gt "Target node has pods" "$pre_pods" 0

start_ts=$(date +%s)
drain_node "$target"

# Wait for all pods to be Running again
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true
end_ts=$(date +%s)
reschedule_seconds=$((end_ts - start_ts))

assert_lt "Reschedule time < 120s" "$reschedule_seconds" 120

add_evidence "timing" "$(jq -n --argjson dur "$reschedule_seconds" --argjson displaced "$pre_pods" \
  '{reschedule_seconds: $dur, pods_displaced: $displaced}')"
finish_test
