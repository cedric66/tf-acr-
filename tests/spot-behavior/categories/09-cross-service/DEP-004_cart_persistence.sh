#!/usr/bin/env bash
# DEP-004: Cart data persists across spot node eviction via Redis
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DEP-004" "Cart persistence across eviction" "cross-service"
trap cleanup_nodes EXIT

# Verify redis is running (stateful, on standard)
redis_running=$(kubectl get pods -n "$NAMESPACE" -l "app=redis" --no-headers 2>/dev/null | grep -c Running || echo 0)
assert_gt "Redis running before test" "$redis_running" 0

# Find spot node hosting cart pods
target=""
for node in $(get_spot_nodes); do
  has_cart=$(kubectl get pods -n "$NAMESPACE" -l "app=cart" --field-selector "spec.nodeName=$node" --no-headers 2>/dev/null | wc -l)
  [[ "$has_cart" -gt 0 ]] && { target="$node"; break; }
done
[[ -z "$target" ]] && skip_test "No spot node hosts cart pods"

drain_node "$target"
sleep 10
wait_for_pods_ready "app=cart" "$POD_READY_TIMEOUT" || true

# Verify cart and redis are still running
cart_running=$(kubectl get pods -n "$NAMESPACE" -l "app=cart" --no-headers 2>/dev/null | grep -c Running || echo 0)
redis_still=$(kubectl get pods -n "$NAMESPACE" -l "app=redis" --no-headers 2>/dev/null | grep -c Running || echo 0)

assert_gt "Cart recovered after drain" "$cart_running" 0
assert_gt "Redis still running (not on spot)" "$redis_still" 0

# Verify cart can reach redis
cart_pod=$(kubectl get pods -n "$NAMESPACE" -l "app=cart" --no-headers 2>/dev/null | awk 'NR==1{print $1}')
if [[ -n "$cart_pod" ]]; then
  redis_resolve=$(kubectl exec "$cart_pod" -n "$NAMESPACE" -- nslookup redis 2>&1 || echo "FAIL")
  assert_not_empty "Cart can resolve redis" "$(echo "$redis_resolve" | grep -v FAIL | head -1)"
fi

finish_test
