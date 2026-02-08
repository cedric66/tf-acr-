#!/usr/bin/env bash
# TOPO-002: Zone TSC has maxSkew=1 and ScheduleAnyway
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "TOPO-002" "Zone maxSkew=1 and ScheduleAnyway" "topology-spread"

for svc in "${STATELESS_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  first_pod=$(echo "$pods_json" | jq '.items[0] // empty')
  [[ -z "$first_pod" || "$first_pod" == "null" ]] && continue

  zone_tsc=$(echo "$first_pod" | jq '.spec.topologySpreadConstraints[]? | select(.topologyKey == "topology.kubernetes.io/zone")')
  [[ -z "$zone_tsc" ]] && { assert_gt "$svc has zone TSC" 0 0; continue; }

  max_skew=$(echo "$zone_tsc" | jq '.maxSkew // -1')
  unsat=$(echo "$zone_tsc" | jq -r '.whenUnsatisfiable // "unknown"')

  assert_eq "$svc zone maxSkew=1" "$max_skew" "1"
  assert_eq "$svc zone whenUnsatisfiable=ScheduleAnyway" "$unsat" "ScheduleAnyway"
done

finish_test
