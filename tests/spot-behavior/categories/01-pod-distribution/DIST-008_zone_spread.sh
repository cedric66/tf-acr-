#!/usr/bin/env bash
# DIST-008: Verify pods are spread across availability zones
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DIST-008" "Pods spread across availability zones" "pod-distribution"

zone_counts='{}'
all_pods=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null)
total_pods=$(echo "$all_pods" | jq '.items | length')

for pod_node in $(echo "$all_pods" | jq -r '.items[].spec.nodeName // empty'); do
  zone=$(get_node_zone "$pod_node")
  [[ -z "$zone" ]] && continue
  zone_counts=$(echo "$zone_counts" | jq --arg z "$zone" '.[$z] = ((.[$z] // 0) + 1)')
done

zones_used=$(echo "$zone_counts" | jq 'keys | length')
assert_gte "Pods in at least 2 zones" "$zones_used" 2

# Check that no zone has more than 60% of pods
for zone in $(echo "$zone_counts" | jq -r 'keys[]'); do
  count=$(echo "$zone_counts" | jq --arg z "$zone" '.[$z]')
  pct=$((count * 100 / total_pods))
  assert_lt "Zone $zone has <60% of pods" "$pct" 60
done

add_evidence "zone_distribution" "$zone_counts"
add_evidence_str "zones_used" "$zones_used"
finish_test
