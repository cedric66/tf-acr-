#!/usr/bin/env bash
# EDGE-004: PDB enforcement even when topology constraints are violated
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EDGE-004" "PDB + topology interaction" "edge-cases"
trap cleanup_nodes EXIT

# Drain 2 spot nodes from the same zone to create topology imbalance
zone_nodes='{}'
for node in $(get_spot_nodes); do
  zone=$(get_node_zone "$node")
  [[ -z "$zone" ]] && continue
  zone_nodes=$(echo "$zone_nodes" | jq --arg z "$zone" --arg n "$node" \
    '.[$z] = ((.[$z] // []) + [$n])')
done

# Find a zone with 2+ nodes
target_zone=""
targets=()
for zone in $(echo "$zone_nodes" | jq -r 'keys[]'); do
  count=$(echo "$zone_nodes" | jq --arg z "$zone" '.[$z] | length')
  if [[ "$count" -ge 2 ]]; then
    target_zone="$zone"
    targets=($(echo "$zone_nodes" | jq -r --arg z "$zone" '.[$z][0:2][]'))
    break
  fi
done

[[ ${#targets[@]} -lt 1 ]] && skip_test "Need zone with 2+ spot nodes"

for t in "${targets[@]}"; do
  drain_node "$t"
done

sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

# Verify PDBs still respected despite topology violation
for svc in "${PDB_SERVICES[@]}"; do
  running=$(kubectl get pods -n "$NAMESPACE" -l "app=$svc" --no-headers 2>/dev/null | grep -c Running || echo 0)
  assert_gte "$svc >= minAvailable(1) despite topology imbalance" "$running" 1
done

add_evidence_str "disrupted_zone" "$target_zone"
finish_test
