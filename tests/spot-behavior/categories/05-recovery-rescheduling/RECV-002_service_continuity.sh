#!/usr/bin/env bash
# RECV-002: Service continuity - running count never drops below PDB minAvailable
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "RECV-002" "Service continuity during drain" "recovery-rescheduling"
trap cleanup_nodes EXIT

target=$(get_spot_nodes | awk '{print $1}')
[[ -z "$target" ]] && skip_test "No spot nodes available"

# Monitor in background while draining
min_running='{}'
drain_node "$target" &
drain_pid=$!

for _ in $(seq 1 20); do
  for svc in "${PDB_SERVICES[@]}"; do
    count=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
    min_running=$(echo "$min_running" | jq --arg s "$svc" --argjson c "$count" \
      'if .[$s] == null or $c < .[$s] then .[$s] = $c else . end')
  done
  sleep 3
done
wait "$drain_pid" || true

for svc in "${PDB_SERVICES[@]}"; do
  min=$(echo "$min_running" | jq --arg s "$svc" '.[$s] // 0')
  assert_gte "$svc never below minAvailable=1" "$min" 1
done

add_evidence "minimum_running" "$min_running"
finish_test
