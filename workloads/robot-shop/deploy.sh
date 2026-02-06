#!/bin/bash
# Deploy Robot Shop to AKS cluster
set -e

NAMESPACE="robot-shop"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Robot Shop Deployment ==="

# Add Helm repo
echo "Adding Helm repo..."
helm repo add robot-shop https://instana.github.io/robot-shop/ 2>/dev/null || true
helm repo update

# Create namespace
echo "Creating namespace..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Deploy
echo "Deploying Robot Shop..."
helm upgrade --install robot-shop robot-shop/robot-shop \
  --namespace ${NAMESPACE} \
  -f "${SCRIPT_DIR}/values-prod.yaml" \
  --wait --timeout 5m

# Verify
echo "Verifying deployment..."
kubectl get pods -n ${NAMESPACE} -o wide

echo "=== Deployment Complete ==="
echo "Access web UI: kubectl port-forward -n ${NAMESPACE} svc/web 8080:8080"
