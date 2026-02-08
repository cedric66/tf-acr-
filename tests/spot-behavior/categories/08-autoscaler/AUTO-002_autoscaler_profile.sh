#!/usr/bin/env bash
# AUTO-002: Verify autoscaler profile settings match expected values
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "AUTO-002" "Autoscaler profile settings" "autoscaler"

profile=$(az aks show -n "$CLUSTER_NAME" -g "$RESOURCE_GROUP" --query "autoScalerProfile" -o json 2>/dev/null || echo '{}')

[[ "$profile" == "{}" ]] && skip_test "Cannot query autoscaler profile (az CLI)"

scan=$(echo "$profile" | jq -r '.scanInterval // "unknown"')
max_grace=$(echo "$profile" | jq -r '.maxGracefulTerminationSec // "unknown"')
scale_down_unready=$(echo "$profile" | jq -r '.scaleDownUnreadyTime // "unknown"')
scale_down_unneeded=$(echo "$profile" | jq -r '.scaleDownUnneededTime // "unknown"')
scale_down_delay_delete=$(echo "$profile" | jq -r '.scaleDownDelayAfterDelete // "unknown"')
max_prov=$(echo "$profile" | jq -r '.maxNodeProvisionTime // "unknown"')
expander=$(echo "$profile" | jq -r '.expander // "unknown"')
skip_system=$(echo "$profile" | jq -r '.skipNodesWithSystemPods // "unknown"')

assert_eq "Expander is priority" "$expander" "priority"
assert_eq "Scan interval is 20s" "$scan" "20s"
assert_eq "Max graceful termination is 60" "$max_grace" "60"
assert_eq "Scale down unready is 3m" "$scale_down_unready" "3m"
assert_eq "Scale down unneeded is 5m" "$scale_down_unneeded" "5m"
assert_eq "Scale down delay after delete is 10s" "$scale_down_delay_delete" "10s"
assert_eq "Max node provisioning time is 10m" "$max_prov" "10m"
assert_eq "Skip nodes with system pods is true" "$skip_system" "true"

add_evidence "autoscaler_profile" "$profile"
finish_test
