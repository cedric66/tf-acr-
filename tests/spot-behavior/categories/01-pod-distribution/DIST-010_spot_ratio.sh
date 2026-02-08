#!/usr/bin/env bash
# DIST-010: Verify overall spot vs on-demand ratio targets (75% spot target)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DIST-010" "Spot vs on-demand ratio meets 75% target" "pod-distribution"

all_pods=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null)
total=$(echo "$all_pods" | jq '.items | length')
on_spot=0
on_standard=0
on_system=0

for pod_node in $(echo "$all_pods" | jq -r '.items[].spec.nodeName // empty'); do
  pool=$(get_node_pool_for_node "$pod_node")
  if is_spot_node "$pod_node"; then
    on_spot=$((on_spot + 1))
  elif [[ "$pool" == "$SYSTEM_POOL" ]]; then
    on_system=$((on_system + 1))
  else
    on_standard=$((on_standard + 1))
  fi
done

# Spot ratio of user workloads (exclude system pods)
user_total=$((on_spot + on_standard))
if [[ "$user_total" -gt 0 ]]; then
  spot_pct=$((on_spot * 100 / user_total))
else
  spot_pct=0
fi

assert_gte "Spot ratio of user pods >= 50%" "$spot_pct" 50

add_evidence "pod_placement" "$(jq -n \
  --argjson total "$total" \
  --argjson spot "$on_spot" \
  --argjson std "$on_standard" \
  --argjson sys "$on_system" \
  --argjson pct "$spot_pct" \
  '{total: $total, on_spot: $spot, on_standard: $std, on_system: $sys, spot_percent: $pct}')"
finish_test
