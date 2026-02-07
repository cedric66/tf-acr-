#!/usr/bin/env bash
# EVICT-002: Verify stateless pods have terminationGracePeriodSeconds=35
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EVICT-002" "Graceful termination period configured" "eviction-behavior"

for svc in "${STATELESS_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  first_pod=$(echo "$pods_json" | jq '.items[0] // empty')
  [[ -z "$first_pod" || "$first_pod" == "null" ]] && continue

  grace=$(echo "$first_pod" | jq '.spec.terminationGracePeriodSeconds // 30')
  assert_eq "$svc terminationGracePeriodSeconds=$TERMINATION_GRACE_PERIOD" "$grace" "$TERMINATION_GRACE_PERIOD"
done

finish_test
