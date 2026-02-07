#!/usr/bin/env bash
# DIST-002: Verify stateful services are NOT running on spot nodes
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DIST-002" "Stateful services not on spot nodes" "pod-distribution"

service_counts='{}'
for svc in "${STATEFUL_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  total=$(echo "$pods_json" | jq '.items | length')
  spot_count=0

  for node_name in $(echo "$pods_json" | jq -r '.items[].spec.nodeName // empty'); do
    if is_spot_node "$node_name"; then
      spot_count=$((spot_count + 1))
    fi
  done

  assert_eq "$svc has zero pods on spot" "$spot_count" "0"
  service_counts=$(echo "$service_counts" | jq \
    --arg s "$svc" --argjson t "$total" --argjson sp "$spot_count" \
    '. + {($s): {total: $t, on_spot: $sp}}')
done

add_evidence "stateful_service_placement" "$service_counts"
finish_test
