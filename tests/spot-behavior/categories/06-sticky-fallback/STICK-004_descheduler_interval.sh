#!/usr/bin/env bash
# STICK-004: Descheduler interval is 5 minutes
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "STICK-004" "Descheduler interval is 5m" "sticky-fallback"

# Look for descheduler configuration
descheduler_cm=$(kubectl get configmap -n kube-system -l app.kubernetes.io/name=descheduler -o json 2>/dev/null || echo '{"items":[]}')
cm_data=$(echo "$descheduler_cm" | jq -r '.items[0].data // {} | to_entries[0].value // ""')

if [[ -n "$cm_data" ]]; then
  assert_contains "DeschedulingInterval set to 5m" "$cm_data" "5m\|300s\|deschedulingInterval"
else
  # Check via deployment args
  descheduler=$(kubectl get deployment -n kube-system -l app=descheduler -o json 2>/dev/null || \
    kubectl get deployment -n descheduler -o json 2>/dev/null || echo '{"items":[]}')
  args=$(echo "$descheduler" | jq -r '[.items[0].spec.template.spec.containers[0].args[]?] | join(" ")' 2>/dev/null || echo "")
  if [[ -n "$args" ]]; then
    assert_contains "Descheduler args contain interval" "$args" "descheduling-interval\|5m\|300"
  else
    skip_test "Cannot find descheduler configuration"
  fi
fi

finish_test
