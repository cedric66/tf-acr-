#!/usr/bin/env bash
# TOPO-001: Zone topology spread constraint present on stateless pods
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "TOPO-001" "Zone spread constraint present" "topology-spread"

for svc in "${STATELESS_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  first_pod=$(echo "$pods_json" | jq '.items[0] // empty')
  [[ -z "$first_pod" || "$first_pod" == "null" ]] && continue

  tsc_count=$(echo "$first_pod" | jq '.spec.topologySpreadConstraints // [] | length')
  assert_gte "$svc has topology spread constraints" "$tsc_count" 1

  has_zone=$(echo "$first_pod" | jq '[.spec.topologySpreadConstraints[]? | select(.topologyKey == "topology.kubernetes.io/zone")] | length')
  assert_gt "$svc has zone TSC" "$has_zone" 0
done

finish_test
