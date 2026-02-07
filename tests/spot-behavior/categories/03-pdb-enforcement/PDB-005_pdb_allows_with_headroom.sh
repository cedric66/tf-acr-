#!/usr/bin/env bash
# PDB-005: PDB allows drain when replicas > minAvailable
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "PDB-005" "PDB allows drain with headroom" "pdb-enforcement"
trap cleanup_nodes EXIT

# Ensure web has 3+ replicas
original_replicas=$(kubectl get deployment web -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 2)
kubectl scale deployment web -n "$NAMESPACE" --replicas=3 2>/dev/null || skip_test "Cannot scale web"
wait_for_pods_ready "app=web" "$POD_READY_TIMEOUT" || true

# Find spot node hosting a web pod
target=""
for node in $(get_spot_nodes); do
  has_web=$(kubectl get pods -n "$NAMESPACE" -l "app=web" --field-selector "spec.nodeName=$node" --no-headers 2>/dev/null | wc -l)
  if [[ "$has_web" -gt 0 ]]; then
    target="$node"
    break
  fi
done
[[ -z "$target" ]] && skip_test "No spot node hosts web pods"

drain_node "$target"

# Check PDB was not violated
running=$(kubectl get pods -n "$NAMESPACE" -l "app=web" --no-headers 2>/dev/null | grep -c Running || echo 0)
assert_gte "Web pods >= minAvailable(1) after drain" "$running" 1

# Restore
kubectl scale deployment web -n "$NAMESPACE" --replicas="$original_replicas" 2>/dev/null || true
wait_for_pods_ready "app=web" "$POD_READY_TIMEOUT" || true

finish_test
