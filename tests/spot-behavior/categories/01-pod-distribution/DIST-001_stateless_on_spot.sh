#!/usr/bin/env bash
# DIST-001: Verify stateless services have pods running on spot nodes
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DIST-001" "Stateless services on spot nodes" "pod-distribution"

service_counts='{}'
for svc in "${STATELESS_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  total=$(echo "$pods_json" | jq '.items | length')
  spot_count=0

  for node_name in $(echo "$pods_json" | jq -r '.items[].spec.nodeName // empty'); do
    if is_spot_node "$node_name"; then
      spot_count=$((spot_count + 1))
    fi
  done

  assert_gt "$svc has pods on spot" "$spot_count" 0
  service_counts=$(echo "$service_counts" | jq \
    --arg s "$svc" --argjson t "$total" --argjson sp "$spot_count" \
    '. + {($s): {total: $t, on_spot: $sp}}')
done

add_evidence "service_pod_counts" "$service_counts"
finish_test
