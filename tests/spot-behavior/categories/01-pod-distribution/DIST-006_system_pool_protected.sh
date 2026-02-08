#!/usr/bin/env bash
# DIST-006: Verify system pool has no user workload pods
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "DIST-006" "System pool has no user workload pods" "pod-distribution"

system_nodes=$(get_system_nodes)
user_pods_on_system=0
evidence='[]'

for node in $system_nodes; do
  pods_json=$(get_pods_on_node "$node")
  # Count non-system pods (exclude kube-system, kube-node-lease, etc.)
  user_pod_count=$(echo "$pods_json" | jq '[.items[]? |
    select(.metadata.namespace != "kube-system" and
           .metadata.namespace != "kube-node-lease" and
           .metadata.namespace != "kube-public" and
           .metadata.namespace != "gatekeeper-system" and
           .metadata.namespace != "calico-system" and
           .metadata.namespace != "tigera-operator")] | length')
  user_pods_on_system=$((user_pods_on_system + user_pod_count))

  if [[ "$user_pod_count" -gt 0 ]]; then
    pod_names=$(echo "$pods_json" | jq -c '[.items[]? |
      select(.metadata.namespace != "kube-system" and
             .metadata.namespace != "kube-node-lease" and
             .metadata.namespace != "kube-public") |
      {name: .metadata.name, namespace: .metadata.namespace}]')
    evidence=$(echo "$evidence" | jq --arg n "$node" --argjson p "$pod_names" \
      '. + [{node: $n, user_pods: $p}]')
  fi
done

assert_eq "No user workload pods on system pool" "$user_pods_on_system" "0"
add_evidence "system_node_user_pods" "$evidence"
finish_test
