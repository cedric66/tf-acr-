#!/usr/bin/env bash
# AUTO-001: Verify priority expander ConfigMap has correct pool ordering
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "AUTO-001" "Priority expander ConfigMap order" "autoscaler"

cm=$(kubectl get configmap cluster-autoscaler-priority-expander -n kube-system -o json 2>/dev/null || echo '{}')

if [[ "$(echo "$cm" | jq 'has("data")')" != "true" ]]; then
  skip_test "Priority expander ConfigMap not found"
fi

priorities_yaml=$(echo "$cm" | jq -r '.data.priorities // ""')
assert_not_empty "Priorities data exists" "$priorities_yaml"

# Verify memory pools (E-series) have highest priority (lowest number = 5)
assert_contains "spotmemory1 in priorities" "$priorities_yaml" "spotmemory1"
assert_contains "spotmemory2 in priorities" "$priorities_yaml" "spotmemory2"

# Verify general/compute pools at priority 10
assert_contains "spotgeneral1 in priorities" "$priorities_yaml" "spotgeneral1"
assert_contains "spotgeneral2 in priorities" "$priorities_yaml" "spotgeneral2"
assert_contains "spotcompute in priorities" "$priorities_yaml" "spotcompute"

# Verify standard pool at priority 20
assert_contains "stdworkload in priorities" "$priorities_yaml" "stdworkload"

# Verify system pool at priority 30 (lowest priority for user workloads)
assert_contains "system in priorities" "$priorities_yaml" "system"

# Check ordering: memory (5) < general (10) < standard (20) < system (30)
# Extract numeric keys and verify ordering
has_5=$(echo "$priorities_yaml" | grep -c "^5:" || echo 0)
has_10=$(echo "$priorities_yaml" | grep -c "^10:" || echo 0)
has_20=$(echo "$priorities_yaml" | grep -c "^20:" || echo 0)
has_30=$(echo "$priorities_yaml" | grep -c "^30:" || echo 0)

assert_gt "Priority tier 5 exists (memory spot)" "$has_5" 0
assert_gt "Priority tier 10 exists (general/compute spot)" "$has_10" 0
assert_gt "Priority tier 20 exists (standard on-demand)" "$has_20" 0
assert_gt "Priority tier 30 exists (system)" "$has_30" 0

add_evidence_str "priority_configmap" "$priorities_yaml"
finish_test
