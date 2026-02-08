#!/usr/bin/env bash
# EVICT-006: Service endpoint removed before pod termination
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EVICT-006" "Service endpoint removal on drain" "eviction-behavior"
trap cleanup_nodes EXIT

# Check web service endpoints
pre_endpoints=$(kubectl get endpoints web -n "$NAMESPACE" -o json 2>/dev/null || echo '{}')
pre_count=$(echo "$pre_endpoints" | jq '[.subsets[]?.addresses[]?] | length')
assert_gt "Web has endpoints before drain" "$pre_count" 0

# Find a spot node hosting web pods
target=""
for node in $(get_spot_nodes); do
  has_web=$(kubectl get pods -n "$NAMESPACE" -l "app=web" --field-selector "spec.nodeName=$node" --no-headers 2>/dev/null | wc -l)
  if [[ "$has_web" -gt 0 ]]; then
    target="$node"
    break
  fi
done
[[ -z "$target" ]] && skip_test "No spot node hosts web pods"

drain_node "$target"

# Check endpoints changed
post_endpoints=$(kubectl get endpoints web -n "$NAMESPACE" -o json 2>/dev/null || echo '{}')
post_count=$(echo "$post_endpoints" | jq '[.subsets[]?.addresses[]?] | length')

# During/after drain, endpoint count should differ
assert_lt "Endpoint count reduced during drain" "$post_count" "$pre_count"

wait_for_pods_ready "app=web" "$POD_READY_TIMEOUT" || true

add_evidence "endpoints" "$(jq -n --argjson pre "$pre_count" --argjson post "$post_count" '{pre: $pre, post_drain: $post}')"
finish_test
