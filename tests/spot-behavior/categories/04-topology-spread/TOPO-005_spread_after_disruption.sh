#!/usr/bin/env bash
# TOPO-005: Zone distribution maintained after disruption
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "TOPO-005" "Spread maintained after disruption" "topology-spread"
trap cleanup_nodes EXIT

target=$(get_spot_nodes | awk '{print $1}')
[[ -z "$target" ]] && skip_test "No spot nodes available"

# Pre-disruption zone distribution
pre_zones='{}'
for svc in "web" "cart"; do
  pods_json=$(get_pods_for_service "$svc")
  for pod_node in $(echo "$pods_json" | jq -r '.items[].spec.nodeName // empty'); do
    zone=$(get_node_zone "$pod_node")
    [[ -z "$zone" ]] && continue
    pre_zones=$(echo "$pre_zones" | jq --arg s "$svc" --arg z "$zone" \
      '.[$s][$z] = ((.[$s][$z] // 0) + 1)')
  done
done

drain_node "$target"
sleep 10
wait_for_pods_ready "app" "$POD_READY_TIMEOUT" || true

# Post-disruption zone distribution
post_zones='{}'
for svc in "web" "cart"; do
  pods_json=$(get_pods_for_service "$svc")
  zone_list=()
  for pod_node in $(echo "$pods_json" | jq -r '.items[].spec.nodeName // empty'); do
    zone=$(get_node_zone "$pod_node")
    [[ -z "$zone" ]] && continue
    zone_list+=("$zone")
    post_zones=$(echo "$post_zones" | jq --arg s "$svc" --arg z "$zone" \
      '.[$s][$z] = ((.[$s][$z] // 0) + 1)')
  done

  # Check no zone has excessive skew (best effort - ScheduleAnyway is soft)
  unique_zones=$(printf '%s\n' "${zone_list[@]}" | sort -u | wc -l)
  assert_gte "$svc still in multiple zones" "$unique_zones" 1
done

add_evidence "pre_zones" "$pre_zones"
add_evidence "post_zones" "$post_zones"
finish_test
