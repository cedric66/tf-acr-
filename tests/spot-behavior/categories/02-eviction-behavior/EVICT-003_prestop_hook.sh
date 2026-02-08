#!/usr/bin/env bash
# EVICT-003: Verify preStop lifecycle hook exists on stateless pods
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EVICT-003" "PreStop hook configured" "eviction-behavior"

for svc in "${STATELESS_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  first_pod=$(echo "$pods_json" | jq '.items[0] // empty')
  [[ -z "$first_pod" || "$first_pod" == "null" ]] && continue

  has_prestop=$(echo "$first_pod" | jq '
    [.spec.containers[]? | select(.lifecycle.preStop != null)] | length')

  assert_gt "$svc has preStop hook" "$has_prestop" 0
done

finish_test
