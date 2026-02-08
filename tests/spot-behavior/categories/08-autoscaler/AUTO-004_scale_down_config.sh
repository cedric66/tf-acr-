#!/usr/bin/env bash
# AUTO-004: Scale-down utilization threshold configured correctly
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "AUTO-004" "Scale-down configuration" "autoscaler"

profile=$(az aks show -n "$CLUSTER_NAME" -g "$RESOURCE_GROUP" --query "autoScalerProfile" -o json 2>/dev/null || echo '{}')
[[ "$profile" == "{}" ]] && skip_test "Cannot query autoscaler profile (az CLI)"

util_threshold=$(echo "$profile" | jq -r '.scaleDownUtilizationThreshold // "unknown"')
delay_after_add=$(echo "$profile" | jq -r '.scaleDownDelayAfterAdd // "unknown"')
delay_after_failure=$(echo "$profile" | jq -r '.scaleDownDelayAfterFailure // "unknown"')
skip_local=$(echo "$profile" | jq -r '.skipNodesWithLocalStorage // "unknown"')
balance=$(echo "$profile" | jq -r '.balanceSimilarNodeGroups // "unknown"')

assert_eq "Utilization threshold is 0.5" "$util_threshold" "0.5"
assert_eq "Delay after add is 10m" "$delay_after_add" "10m"
assert_eq "Delay after failure is 3m" "$delay_after_failure" "3m"
assert_eq "Skip local storage is false" "$skip_local" "false"
assert_eq "Balance similar node groups is true" "$balance" "true"

finish_test
