#!/usr/bin/env bash
# cluster-spot-readiness.sh - Full cluster audit for spot migration
# Usage: ./cluster-spot-readiness.sh
# Loads configuration from config.sh
# Reference: .env.example and README.md

set -euo pipefail

# Determine script directory to source config.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/config.sh" ]]; then
    source "${SCRIPT_DIR}/config.sh"
else
    echo "Error: config.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

echo "=============================================="
echo "AKS Cluster Spot Migration Readiness Report"
echo "Date: $(date)"
echo "Cluster: ${CLUSTER_NAME}"
echo "=============================================="

echo ""
echo "=== Cluster Info ==="
kubectl cluster-info | head -1
echo "Nodes: $(kubectl get nodes --no-headers | wc -l)"
echo "Namespaces: $(kubectl get ns --no-headers | wc -l)"

echo ""
echo "=== Current Node Distribution ==="
TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo 0)
SPOT_NODES=$(kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot --no-headers 2>/dev/null | wc -l || echo 0)
SYSTEM_NODES=$(kubectl get nodes -l agentpool=system --no-headers 2>/dev/null | wc -l || echo 0)
USER_ONDEMAND=$((TOTAL_NODES - SPOT_NODES - SYSTEM_NODES))

echo "Total Nodes: $TOTAL_NODES"
echo "Spot:        $SPOT_NODES"
echo "On-Demand:   $USER_ONDEMAND (user pools)"
echo "System:      $SYSTEM_NODES"

echo ""
echo "=== Deployment Readiness by Namespace ==="
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -vE "^(kube-|gatekeeper-system|calico-system|azure-arc)"); do
  TOTAL=$(kubectl get deployments -n "$ns" --no-headers 2>/dev/null | wc -l || echo 0)
  if [[ "$TOTAL" -gt 0 ]]; then
    echo ""
    echo "--- Namespace: $ns ($TOTAL deployments) ---"
    kubectl get deployments -n "$ns" -o json 2>/dev/null | 
      jq -r '.items[] |
        .metadata.name as $name |
        .spec.replicas as $replicas |
        (.spec.template.spec.containers // []) as $containers |
        (
          if (.spec.template.spec.volumes // [] | any(.persistentVolumeClaim)) then
            "  ❌ NEVER  \($name) (stateful - has PVC)"
          elif ($replicas < 2) then
            "  ⚠️  MAYBE  \($name) (\($replicas) replica)"
          elif ($containers | any(.lifecycle.preStop == null)) then
            "  ⚠️  MAYBE  \($name) (one or more containers missing preStop hook)"
          else
            "  ✅ READY  \($name) (\($replicas) replicas)"
          end
        )'
  fi
done

echo ""
echo "=== Summary ==="
TOTAL_DEPS=$(kubectl get deployments -A --no-headers | wc -l)
echo "Total deployments across all namespaces: $TOTAL_DEPS"
echo ""
echo "Run ./spot-readiness-audit.sh [namespace] for detailed assessment."
echo "=============================================="
