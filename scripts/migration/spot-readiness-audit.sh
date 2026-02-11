#!/usr/bin/env bash
# spot-readiness-audit.sh - Scan deployments for spot eligibility
# Usage: ./spot-readiness-audit.sh [namespace]
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

NAMESPACE="${1:-${K8S_NAMESPACE:-default}}"

echo "=== Spot Readiness Audit: namespace=$NAMESPACE ==="
echo ""

# Check if namespace exists
if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
  echo "Error: Namespace '$NAMESPACE' not found."
  exit 1
fi

# Audit deployments
kubectl get deployments -n "$NAMESPACE" -o json | 
  jq -r '.items[] | {
    name: .metadata.name,
    replicas: .spec.replicas,
    has_toleration: (
      .spec.template.spec.tolerations // [] |
      any(.key == "kubernetes.azure.com/scalesetpriority" and .value == "spot")
    ),
    has_pdb: false, # Placeholder for more complex check if needed
    has_prestop: (
      .spec.template.spec.containers // [] |
      all(.lifecycle.preStop != null)
    ),
    has_readiness: (
      .spec.template.spec.containers // [] |
      all(.readinessProbe != null)
    ),
    termination_grace: (
      .spec.template.spec.terminationGracePeriodSeconds // 30
    ),
    volumes: (
      .spec.template.spec.volumes // [] | map(.name) | join(",")
    )
  }' | jq -s '.'

echo ""
echo "=== Classification ==="
echo ""

kubectl get deployments -n "$NAMESPACE" -o json | 
  jq -r '.items[] |
    .metadata.name as $name |
    .spec.replicas as $replicas |
    (.spec.template.spec.containers // []) as $containers |
    (
      if (.spec.template.spec.volumes // [] | any(.persistentVolumeClaim)) then
        "❌ NEVER  - \($name) (has PVC - stateful)"
      elif ($replicas < 2) then
        "⚠️  MAYBE  - \($name) (only \($replicas) replica - increase before spot)"
      elif ($containers | any(.lifecycle.preStop == null)) then
        "⚠️  MAYBE  - \($name) (missing preStop hook in one or more containers)"
      else
        "✅ READY  - \($name) (\($replicas) replicas, has preStop)"
      end
    )'
