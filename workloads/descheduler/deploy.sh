#!/bin/bash
# Deploy Descheduler to AKS cluster
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Descheduler Deployment ==="

# Add Helm repo
echo "Adding Helm repo..."
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler/ 2>/dev/null || true
helm repo update

# Deploy
echo "Deploying Descheduler..."
helm upgrade --install descheduler descheduler/descheduler \
  -n kube-system \
  -f "${SCRIPT_DIR}/values.yaml" \
  --wait --timeout 2m

# Verify
echo "Verifying deployment..."
kubectl get pods -n kube-system -l app.kubernetes.io/name=descheduler

echo "=== Deployment Complete ==="
