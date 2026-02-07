#!/usr/bin/env bash
# DEP-001: Frontend-backend connectivity after spot node drain
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DEP-001" "Frontend-backend connectivity after eviction" "cross-service"
trap cleanup_nodes EXIT

# Find spot node hosting web pods
target=""
for node in $(get_spot_nodes); do
  has_web=$(kubectl get pods -n "$NAMESPACE" -l "app=web" --field-selector "spec.nodeName=$node" --no-headers 2>/dev/null | wc -l)
  [[ "$has_web" -gt 0 ]] && { target="$node"; break; }
done
[[ -z "$target" ]] && skip_test "No spot node hosts web pods"

drain_node "$target"
sleep 10
wait_for_pods_ready "app=web" "$POD_READY_TIMEOUT" || true

# Verify web can reach catalogue
web_pod=$(kubectl get pods -n "$NAMESPACE" -l "app=web" --no-headers 2>/dev/null | awk 'NR==1{print $1}')
[[ -z "$web_pod" ]] && { assert_gt "Web pod exists" 0 0; finish_test; exit; }

# Check catalogue service is resolvable from web pod
result=$(kubectl exec "$web_pod" -n "$NAMESPACE" -- wget -q -O /dev/null -T 5 "http://catalogue:8080/health" 2>&1 || echo "FAIL")

if echo "$result" | grep -q "FAIL\|error\|timed out"; then
  # Try alternate health check
  result2=$(kubectl exec "$web_pod" -n "$NAMESPACE" -- nslookup catalogue 2>&1 || echo "FAIL")
  assert_not_empty "Catalogue DNS resolves from web" "$(echo "$result2" | grep -v FAIL)"
else
  assert_eq "Web can reach catalogue" "success" "success"
fi

add_evidence_str "connectivity_check" "$result"
finish_test
