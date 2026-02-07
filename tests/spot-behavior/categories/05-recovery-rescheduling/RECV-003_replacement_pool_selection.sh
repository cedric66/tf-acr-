#!/usr/bin/env bash
# RECV-003: Displaced pods prefer spot pools for rescheduling
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "RECV-003" "Replacement pool selection prefers spot" "recovery-rescheduling"
trap cleanup_nodes EXIT

target=$(get_spot_nodes | awk '{print $1}')
[[ -z "$target" ]] && skip_test "No spot nodes available"

# Record which services are on the target
displaced_svcs=()
for svc in "${STATELESS_SERVICES[@]}"; do
  count=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --field-selector "spec.nodeName=$target" --no-headers 2>/dev/null | wc -l)
  [[ "$count" -gt 0 ]] && displaced_svcs+=("$svc")
done

drain_node "$target"
sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

# Check where displaced services landed
on_spot=0
on_standard=0
for svc in "${displaced_svcs[@]}"; do
  for node in $(kubectl get pods -n "$NAMESPACE" -l "app=$svc" -o jsonpath='{.items[*].spec.nodeName}' 2>/dev/null); do
    if is_spot_node "$node"; then
      on_spot=$((on_spot + 1))
    else
      on_standard=$((on_standard + 1))
    fi
  done
done

total=$((on_spot + on_standard))
if [[ "$total" -gt 0 ]]; then
  spot_pct=$((on_spot * 100 / total))
  assert_gte "Majority of replacement pods on spot (>=50%)" "$spot_pct" 50
fi

add_evidence "replacement_placement" "$(jq -n --argjson spot "$on_spot" --argjson std "$on_standard" '{on_spot: $spot, on_standard: $std}')"
finish_test
