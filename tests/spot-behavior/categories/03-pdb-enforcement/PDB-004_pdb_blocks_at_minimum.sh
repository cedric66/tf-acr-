#!/usr/bin/env bash
# PDB-004: PDB blocks disruption when at minimum replicas
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "PDB-004" "PDB blocks disruption at minimum" "pdb-enforcement"
trap cleanup_nodes EXIT

# Scale web to 1 replica
original_replicas=$(kubectl get deployment web -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 2)
kubectl scale deployment web -n "$NAMESPACE" --replicas=1 2>/dev/null || skip_test "Cannot scale web"
sleep 15

# Get the single web pod
web_pod=$(kubectl get pods -n "$NAMESPACE" -l "app=web" --no-headers 2>/dev/null | awk 'NR==1{print $1}')
[[ -z "$web_pod" ]] && skip_test "No web pod found"

# Check that PDB disruptionsAllowed is 0
allowed=$(kubectl get pdb -n "$NAMESPACE" -o json 2>/dev/null | \
  jq '[.items[] | select(.metadata.name | contains("web"))] | .[0].status.disruptionsAllowed // -1')
assert_eq "Web PDB disruptionsAllowed=0 at 1 replica" "$allowed" "0"

# Try to evict - should fail
eviction_result=$(kubectl create -f - -o json 2>&1 <<EOF || echo "BLOCKED"
apiVersion: policy/v1
kind: Eviction
metadata:
  name: $web_pod
  namespace: $NAMESPACE
EOF
)

assert_contains "Eviction blocked by PDB" "$eviction_result" "BLOCKED\|Cannot evict\|disruption budget"

# Restore original replicas
kubectl scale deployment web -n "$NAMESPACE" --replicas="$original_replicas" 2>/dev/null || true
wait_for_pods_ready "app=web" "$POD_READY_TIMEOUT" || true

finish_test
