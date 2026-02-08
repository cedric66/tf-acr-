#!/usr/bin/env bash
# DIST-009: Verify topology spread constraints are applied to stateless pods
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DIST-009" "Topology spread constraints applied" "pod-distribution"

for svc in "${STATELESS_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  first_pod=$(echo "$pods_json" | jq '.items[0] // empty')
  [[ -z "$first_pod" || "$first_pod" == "null" ]] && continue

  # Check for zone topology spread
  has_zone_spread=$(echo "$first_pod" | jq '
    [.spec.topologySpreadConstraints[]? |
     select(.topologyKey == "topology.kubernetes.io/zone")] | length')

  assert_gt "$svc has zone topology spread" "$has_zone_spread" 0

  # Check whenUnsatisfiable is ScheduleAnyway (soft constraint)
  schedule_anyway=$(echo "$first_pod" | jq '
    [.spec.topologySpreadConstraints[]? |
     select(.topologyKey == "topology.kubernetes.io/zone" and
            .whenUnsatisfiable == "ScheduleAnyway")] | length')

  assert_gt "$svc zone spread uses ScheduleAnyway" "$schedule_anyway" 0
done

finish_test
