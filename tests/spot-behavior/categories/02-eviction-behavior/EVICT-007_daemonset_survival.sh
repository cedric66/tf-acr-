#!/usr/bin/env bash
# EVICT-007: DaemonSets ignored during spot node drain
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EVICT-007" "DaemonSet survival during drain" "eviction-behavior"
trap cleanup_nodes EXIT

target=$(get_spot_nodes | awk '{print $1}')
[[ -z "$target" ]] && skip_test "No spot nodes available"

# Count daemonset pods on the node before drain
pre_ds=$(kubectl get pods --all-namespaces --field-selector "spec.nodeName=$target" -o json 2>/dev/null | \
  jq '[.items[] | select(.metadata.ownerReferences[]?.kind == "DaemonSet")] | length')

# Drain uses --ignore-daemonsets (our drain_node does this)
drain_node "$target"

# DaemonSet pods should not be evicted (they stay on the node)
post_ds=$(kubectl get pods --all-namespaces --field-selector "spec.nodeName=$target" -o json 2>/dev/null | \
  jq '[.items[] | select(.metadata.ownerReferences[]?.kind == "DaemonSet")] | length')

# After drain, only DaemonSet pods should remain
non_ds=$(kubectl get pods --all-namespaces --field-selector "spec.nodeName=$target" -o json 2>/dev/null | \
  jq '[.items[] | select((.metadata.ownerReferences[]?.kind == "DaemonSet") | not)] | length')

assert_eq "No non-DaemonSet pods on drained node" "$non_ds" "0"
add_evidence "daemonset_pods" "$(jq -n --argjson pre "$pre_ds" --argjson post "$post_ds" '{before: $pre, after: $post}')"
finish_test
