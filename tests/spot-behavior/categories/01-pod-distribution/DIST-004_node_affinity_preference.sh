#!/usr/bin/env bash
# DIST-004: Verify stateless pods prefer spot nodes via node affinity weight
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DIST-004" "Node affinity prefers spot (weight 100 vs 50)" "pod-distribution"

for svc in "${STATELESS_SERVICES[@]}"; do
  pods_json=$(get_pods_for_service "$svc")
  first_pod=$(echo "$pods_json" | jq '.items[0] // empty')
  [[ -z "$first_pod" || "$first_pod" == "null" ]] && continue

  # Check for preferred spot affinity with weight 100
  spot_weight=$(echo "$first_pod" | jq '
    [.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[]? |
     select(.preference.matchExpressions[]? |
       .key == "kubernetes.azure.com/scalesetpriority" and (.values | index("spot")))
     | .weight] | max // 0')

  assert_gte "$svc spot affinity weight" "$spot_weight" 100
done

finish_test
