#!/usr/bin/env bash
# AUTO-005: Balance similar node groups enabled
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "AUTO-005" "Balance similar node groups enabled" "autoscaler"

profile=$(az aks show -n "$CLUSTER_NAME" -g "$RESOURCE_GROUP" --query "autoScalerProfile" -o json 2>/dev/null || echo '{}')
[[ "$profile" == "{}" ]] && skip_test "Cannot query autoscaler profile (az CLI)"

balance=$(echo "$profile" | jq -r '.balanceSimilarNodeGroups // "unknown"')
assert_eq "Balance similar node groups is true" "$balance" "true"

# Verify node counts across similar pools are roughly balanced
declare -A pool_counts
for pool in "${SPOT_POOLS[@]}"; do
  pool_counts[$pool]=$(count_ready_nodes_in_pool "$pool")
done

evidence='{}'
for pool in "${SPOT_POOLS[@]}"; do
  evidence=$(echo "$evidence" | jq --arg p "$pool" --argjson c "${pool_counts[$pool]}" '. + {($p): $c}')
done

add_evidence "pool_node_counts" "$evidence"
finish_test
