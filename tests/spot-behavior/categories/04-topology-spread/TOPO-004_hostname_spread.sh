#!/usr/bin/env bash
# TOPO-004: Hostname TSC with maxSkew=1
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "TOPO-004" "Hostname spread maxSkew=1" "topology-spread"

for svc in "${STATELESS_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  first_pod=$(echo "$pods_json" | jq '.items[0] // empty')
  [[ -z "$first_pod" || "$first_pod" == "null" ]] && continue

  hostname_tsc=$(echo "$first_pod" | jq '.spec.topologySpreadConstraints[]? | select(.topologyKey == "kubernetes.io/hostname")')

  if [[ -z "$hostname_tsc" ]]; then
    assert_gt "$svc has hostname TSC" 0 0
    continue
  fi

  max_skew=$(echo "$hostname_tsc" | jq '.maxSkew // -1')
  unsat=$(echo "$hostname_tsc" | jq -r '.whenUnsatisfiable // "unknown"')

  assert_eq "$svc hostname maxSkew=1" "$max_skew" "1"
  assert_eq "$svc hostname whenUnsatisfiable=ScheduleAnyway" "$unsat" "ScheduleAnyway"
done

finish_test
