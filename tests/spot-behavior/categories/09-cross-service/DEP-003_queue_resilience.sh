#!/usr/bin/env bash
# DEP-003: Queue service resilience after spot node drain
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DEP-003" "Queue service resilience" "cross-service"
trap cleanup_nodes EXIT

# Find spot node with dispatch or shipping pods
target=""
for node in $(get_spot_nodes); do
  has_queue_consumer=$(kubectl get pods -n "$NAMESPACE" --field-selector "spec.nodeName=$node" -o json 2>/dev/null | \
    jq '[.items[] | select(.metadata.labels.app == "dispatch" or .metadata.labels.app == "shipping")] | length')
  [[ "$has_queue_consumer" -gt 0 ]] && { target="$node"; break; }
done
[[ -z "$target" ]] && skip_test "No spot node hosts dispatch/shipping pods"

drain_node "$target"
sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

# Verify rabbitmq still accessible and consumers recovered
rabbitmq_running=$(kubectl get pods -n "$NAMESPACE" -l "app=rabbitmq" --no-headers 2>/dev/null | grep -c Running || echo 0)
dispatch_running=$(kubectl get pods -n "$NAMESPACE" -l "app=dispatch" --no-headers 2>/dev/null | grep -c Running || echo 0)
shipping_running=$(kubectl get pods -n "$NAMESPACE" -l "app=shipping" --no-headers 2>/dev/null | grep -c Running || echo 0)

assert_gt "RabbitMQ running" "$rabbitmq_running" 0
assert_gt "Dispatch recovered" "$dispatch_running" 0
assert_gt "Shipping recovered" "$shipping_running" 0

finish_test
