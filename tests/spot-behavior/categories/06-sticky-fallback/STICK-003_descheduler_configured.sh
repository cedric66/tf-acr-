#!/usr/bin/env bash
# STICK-003: Descheduler configured with RemovePodsViolatingNodeAffinity
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "STICK-003" "Descheduler configured" "sticky-fallback"

# Check descheduler deployment exists
descheduler=$(kubectl get deployment -n kube-system -l app=descheduler -o json 2>/dev/null || \
  kubectl get deployment -n descheduler -o json 2>/dev/null || \
  kubectl get cronjob -n kube-system -l app=descheduler -o json 2>/dev/null || echo '{"items":[]}')

has_descheduler=$(echo "$descheduler" | jq '.items | length // 0')
if [[ "$has_descheduler" -eq 0 ]]; then
  # Try via helm release
  helm_release=$(kubectl get configmap -n kube-system -l app.kubernetes.io/name=descheduler -o json 2>/dev/null || echo '{"items":[]}')
  has_descheduler=$(echo "$helm_release" | jq '.items | length // 0')
fi
assert_gt "Descheduler deployment exists" "$has_descheduler" 0

# Check for RemovePodsViolatingNodeAffinity strategy in configmap
descheduler_cm=$(kubectl get configmap -n kube-system -l app.kubernetes.io/name=descheduler -o json 2>/dev/null || echo '{"items":[]}')
cm_data=$(echo "$descheduler_cm" | jq -r '.items[0].data // {} | to_entries[0].value // ""')

if [[ -n "$cm_data" ]]; then
  assert_contains "Has RemovePodsViolatingNodeAffinity" "$cm_data" "RemovePodsViolatingNodeAffinity"
else
  # Check in descheduler args
  args=$(echo "$descheduler" | jq -r '.items[0].spec.template.spec.containers[0].args[]? // ""')
  assert_not_empty "Descheduler has configuration" "$args"
fi

finish_test
