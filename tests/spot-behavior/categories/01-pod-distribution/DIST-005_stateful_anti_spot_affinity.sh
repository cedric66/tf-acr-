#!/usr/bin/env bash
# DIST-005: Verify stateful pods have required anti-spot node affinity
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DIST-005" "Stateful pods require non-spot nodes" "pod-distribution"

for svc in "${STATEFUL_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  first_pod=$(echo "$pods_json" | jq '.items[0] // empty')
  [[ -z "$first_pod" || "$first_pod" == "null" ]] && { assert_gt "$svc has pods" 0 0; continue; }

  # Check requiredDuringScheduling with NotIn spot
  has_anti_spot=$(echo "$first_pod" | jq '
    [.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[]? |
     .matchExpressions[]? |
     select(.key == "kubernetes.azure.com/scalesetpriority" and .operator == "NotIn" and (.values | index("spot")))
    ] | length')

  assert_gt "$svc has anti-spot required affinity" "$has_anti_spot" 0
done

finish_test
