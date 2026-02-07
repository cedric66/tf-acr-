#!/usr/bin/env bash
# DEP-002: Database service connectivity after node drain
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DEP-002" "Database connectivity after node drain" "cross-service"
trap cleanup_nodes EXIT

target=$(get_spot_nodes | awk '{print $1}')
[[ -z "$target" ]] && skip_test "No spot nodes available"

drain_node "$target"
sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

# Verify database services still have endpoints
for db_svc in "mongodb" "mysql" "redis"; do
  endpoints=$(kubectl get endpoints "$db_svc" -n "$NAMESPACE" -o json 2>/dev/null || echo '{}')
  ep_count=$(echo "$endpoints" | jq '[.subsets[]?.addresses[]?] | length')
  assert_gt "$db_svc has endpoints after drain" "$ep_count" 0

  # Verify the database pod is Running
  running=$(kubectl get pods -n "$NAMESPACE" -l "app=$db_svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
  assert_gt "$db_svc pod running" "$running" 0
done

finish_test
