#!/usr/bin/env bash
# DIST-003: Verify stateless pods have spot tolerations
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DIST-003" "Stateless pods have spot tolerations" "pod-distribution"

for svc in "${STATELESS_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  first_pod=$(echo "$pods_json" | jq '.items[0] // empty')
  [[ -z "$first_pod" || "$first_pod" == "null" ]] && { assert_gt "$svc has pods" 0 0; continue; }

  has_toleration=$(echo "$first_pod" | jq '[
    .spec.tolerations[]? |
    select(.key == "kubernetes.azure.com/scalesetpriority" and .value == "spot" and .effect == "NoSchedule")
  ] | length')

  assert_gt "$svc has spot toleration" "$has_toleration" 0
done

finish_test
