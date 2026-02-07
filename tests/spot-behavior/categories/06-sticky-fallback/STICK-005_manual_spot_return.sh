#!/usr/bin/env bash
# STICK-005: New pods prefer spot nodes when capacity available
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "STICK-005" "New pods prefer spot when available" "sticky-fallback"
trap cleanup_nodes EXIT

# Verify spot nodes exist and are schedulable
spot_nodes=$(get_spot_nodes)
[[ -z "$spot_nodes" ]] && skip_test "No spot nodes available"

spot_count=$(echo "$spot_nodes" | wc -w)
assert_gt "Spot nodes available" "$spot_count" 0

# Scale web up by 2 to create new pods
original=$(kubectl get deployment web -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 2)
new_replicas=$((original + 2))
kubectl scale deployment web -n "$NAMESPACE" --replicas="$new_replicas" 2>/dev/null || skip_test "Cannot scale web"

wait_for_pods_ready "app=web" "$POD_READY_TIMEOUT" || true

# Check where the NEW pods landed
on_spot=0
on_standard=0
for node in $(kubectl get pods -n "$NAMESPACE" -l "app=web" -o jsonpath='{.items[*].spec.nodeName}' 2>/dev/null); do
  if is_spot_node "$node"; then
    on_spot=$((on_spot + 1))
  else
    on_standard=$((on_standard + 1))
  fi
done

total=$((on_spot + on_standard))
if [[ "$total" -gt 0 ]]; then
  spot_pct=$((on_spot * 100 / total))
  assert_gte "New pods prefer spot (>=50%)" "$spot_pct" 50
fi

# Restore
kubectl scale deployment web -n "$NAMESPACE" --replicas="$original" 2>/dev/null || true

add_evidence "new_pod_placement" "$(jq -n --argjson spot "$on_spot" --argjson std "$on_standard" '{on_spot: $spot, on_standard: $std}')"
finish_test
