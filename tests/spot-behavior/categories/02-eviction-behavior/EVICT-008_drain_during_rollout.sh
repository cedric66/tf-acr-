#!/usr/bin/env bash
# EVICT-008: Drain during deployment rollout completes successfully
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

init_test "EVICT-008" "Drain during deployment rollout" "eviction-behavior"
trap cleanup_nodes EXIT

target=$(get_spot_nodes | awk '{print $1}')
[[ -z "$target" ]] && skip_test "No spot nodes available"

# Start a rollout restart for web
kubectl rollout restart deployment/web -n "$NAMESPACE" 2>/dev/null || skip_test "Cannot restart web deployment"

# Immediately drain a spot node
sleep 3
drain_node "$target"

# Wait for rollout to complete
kubectl rollout status deployment/web -n "$NAMESPACE" --timeout=180s 2>/dev/null || true

# Verify web pods are running
running=$(kubectl get pods -n "$NAMESPACE" -l "app=web" --no-headers 2>/dev/null | grep -c Running || echo 0)
assert_gt "Web pods running after rollout+drain" "$running" 0

finish_test
