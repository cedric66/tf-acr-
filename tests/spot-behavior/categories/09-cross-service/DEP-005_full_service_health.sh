#!/usr/bin/env bash
# DEP-005: Full service mesh health after drain and recovery
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DEP-005" "Full service mesh health" "cross-service"
trap cleanup_nodes EXIT

target=$(get_spot_nodes | awk '{print $1}')
[[ -z "$target" ]] && skip_test "No spot nodes available"

drain_node "$target"
sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

# Verify all 12 services have running pods
service_health='{}'
all_healthy=true
for svc in "${ALL_SERVICES[@]}"; do
  running=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
  assert_gt "$svc running" "$running" 0
  [[ "$running" -eq 0 ]] && all_healthy=false

  # Check endpoints
  ep_count=$(kubectl get endpoints "$svc" -n "$NAMESPACE" -o json 2>/dev/null | jq '[.subsets[]?.addresses[]?] | length' || echo 0)
  service_health=$(echo "$service_health" | jq --arg s "$svc" --argjson r "$running" --argjson e "$ep_count" \
    '. + {($s): {running: $r, endpoints: $e}}')
done

add_evidence "service_health" "$service_health"
finish_test
