#!/usr/bin/env bash
# EVICT-005: PDBs respected during drain - running count never below minAvailable
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EVICT-005" "PDB respected during drain" "eviction-behavior"
trap cleanup_nodes EXIT

target=$(get_spot_nodes | awk '{print $1}')
[[ -z "$target" ]] && skip_test "No spot nodes available"

# Record pre-drain counts
declare -A pre_counts
for svc in "${PDB_SERVICES[@]}"; do
  pre_counts[$svc]=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
done

# Drain in background and monitor
drain_node "$target" &
drain_pid=$!

min_seen='{}'
for _ in $(seq 1 12); do
  for svc in "${PDB_SERVICES[@]}"; do
    running=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
    min_seen=$(echo "$min_seen" | jq --arg s "$svc" --argjson r "$running" \
      'if .[$s] == null or $r < .[$s] then .[$s] = $r else . end')
  done
  sleep 5
done
wait "$drain_pid" || true

for svc in "${PDB_SERVICES[@]}"; do
  min_val=$(echo "$min_seen" | jq --arg s "$svc" '.[$s] // 0')
  assert_gte "$svc never below minAvailable=1" "$min_val" 1
done

add_evidence "minimum_running_observed" "$min_seen"
finish_test
