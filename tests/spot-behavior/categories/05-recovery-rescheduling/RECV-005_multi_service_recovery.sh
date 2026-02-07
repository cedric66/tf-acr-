#!/usr/bin/env bash
# RECV-005: Multi-service recovery after shared node drain
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "RECV-005" "Multi-service recovery from shared node" "recovery-rescheduling"
trap cleanup_nodes EXIT

# Find a spot node hosting pods from >=2 different services
target=""
max_svcs=0
for node in $(get_spot_nodes); do
  svc_count=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$node" -o json 2>/dev/null | \
    jq '[.items[].metadata.labels.app // empty] | unique | length')
  if (( svc_count > max_svcs )); then
    max_svcs=$svc_count
    target="$node"
  fi
done

[[ -z "$target" || "$max_svcs" -lt 2 ]] && skip_test "No node hosts pods from >=2 services"

# Record affected services
affected=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$target" -o json 2>/dev/null | \
  jq -r '[.items[].metadata.labels.app // empty] | unique | .[]')

drain_node "$target"
sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

for svc in $affected; do
  running=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
  assert_gt "$svc recovered after drain" "$running" 0
done

add_evidence_str "affected_services" "$(echo $affected | tr '\n' ',')"
add_evidence_str "services_on_node" "$max_svcs"
finish_test
