#!/usr/bin/env bash
# TOPO-003: Priority type TSC with maxSkew=2 on scalesetpriority
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "TOPO-003" "Priority type spread maxSkew=2" "topology-spread"

for svc in "${STATELESS_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  first_pod=$(echo "$pods_json" | jq '.items[0] // empty')
  [[ -z "$first_pod" || "$first_pod" == "null" ]] && continue

  priority_tsc=$(echo "$first_pod" | jq '.spec.topologySpreadConstraints[]? | select(.topologyKey == "kubernetes.azure.com/scalesetpriority")')

  if [[ -z "$priority_tsc" ]]; then
    assert_gt "$svc has priority TSC" 0 0
    continue
  fi

  max_skew=$(echo "$priority_tsc" | jq '.maxSkew // -1')
  unsat=$(echo "$priority_tsc" | jq -r '.whenUnsatisfiable // "unknown"')

  assert_eq "$svc priority maxSkew=2" "$max_skew" "2"
  assert_eq "$svc priority whenUnsatisfiable=ScheduleAnyway" "$unsat" "ScheduleAnyway"
done

finish_test
