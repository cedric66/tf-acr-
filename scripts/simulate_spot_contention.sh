#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Spot Contention Simulation Script
# ─────────────────────────────────────────────────────────────────────────────
#
# This script simulates Spot capacity contention scenarios using a local Kind
# cluster. It demonstrates:
#   1. Spot node stockout (all spot nodes unavailable)
#   2. Automatic fallback to on-demand nodes
#   3. Workload resilience during capacity constraints
#
# Usage:
#   ./simulate_spot_contention.sh [setup|run|cleanup|all]
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

CLUSTER_NAME="spot-contention-sim"
NAMESPACE="default"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ─────────────────────────────────────────────────────────────────────────────
# KIND CLUSTER CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

create_kind_config() {
  cat <<EOF > /tmp/kind-spot-contention.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  # Simulated "On-Demand" nodes (always available)
  - role: worker
    labels:
      node-type: on-demand
      capacity-type: on-demand
  # Simulated "Spot" nodes (can be made unavailable)
  - role: worker
    labels:
      node-type: spot
      capacity-type: spot
      sku-family: D
  - role: worker
    labels:
      node-type: spot
      capacity-type: spot
      sku-family: E
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# WORKLOAD MANIFESTS
# ─────────────────────────────────────────────────────────────────────────────

create_workload_manifest() {
  cat <<EOF > /tmp/spot-workload.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spot-tolerant-workload
  namespace: ${NAMESPACE}
spec:
  replicas: 6
  selector:
    matchLabels:
      app: spot-workload
  template:
    metadata:
      labels:
        app: spot-workload
    spec:
      # Tolerate spot taints
      tolerations:
        - key: capacity-type
          operator: Equal
          value: spot
          effect: NoSchedule
      # Prefer spot, allow on-demand fallback
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: capacity-type
                    operator: In
                    values: [spot]
            - weight: 50
              preference:
                matchExpressions:
                  - key: capacity-type
                    operator: In
                    values: [on-demand]
      # Spread across nodes
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: spot-workload
      containers:
        - name: nginx
          image: nginx:alpine
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────────────────────

setup() {
  log_info "Creating Kind cluster: ${CLUSTER_NAME}"
  
  # Delete existing cluster if present
  kind delete cluster --name ${CLUSTER_NAME} 2>/dev/null || true
  
  create_kind_config
  kind create cluster --name ${CLUSTER_NAME} --config /tmp/kind-spot-contention.yaml
  
  log_info "Waiting for nodes to be ready..."
  kubectl wait --for=condition=Ready nodes --all --timeout=120s
  
  log_info "Applying spot taint to spot nodes..."
  SPOT_NODES=$(kubectl get nodes -l capacity-type=spot -o jsonpath='{.items[*].metadata.name}')
  for node in $SPOT_NODES; do
    kubectl taint nodes "$node" capacity-type=spot:NoSchedule --overwrite
    log_ok "Tainted $node as spot"
  done
  
  log_info "Cluster setup complete!"
  kubectl get nodes -L capacity-type,sku-family
}

# ─────────────────────────────────────────────────────────────────────────────
# RUN SIMULATION
# ─────────────────────────────────────────────────────────────────────────────

run_simulation() {
  log_info "=== SCENARIO: Spot Capacity Contention Simulation ==="
  
  # Step 1: Deploy workload
  log_info "Step 1: Deploying workload (6 replicas)..."
  create_workload_manifest
  kubectl apply -f /tmp/spot-workload.yaml
  
  log_info "Waiting for pods to be scheduled..."
  sleep 5
  kubectl get pods -o wide
  
  # Step 2: Show initial distribution
  log_info "Step 2: Initial pod distribution..."
  echo ""
  kubectl get pods -o wide | awk 'NR==1 || /spot-workload/' | column -t
  echo ""
  
  SPOT_COUNT=$(kubectl get pods -o wide | grep "spot-contention-sim-worker[23]" | wc -l || echo 0)
  ONDEMAND_COUNT=$(kubectl get pods -o wide | grep "spot-contention-sim-worker " | wc -l || echo 0)
  log_ok "Pods on Spot nodes: ${SPOT_COUNT}, On-Demand nodes: ${ONDEMAND_COUNT}"
  
  # Step 3: Simulate spot stockout
  log_warn "Step 3: Simulating SPOT STOCKOUT (cordoning all spot nodes)..."
  SPOT_NODES=$(kubectl get nodes -l capacity-type=spot -o jsonpath='{.items[*].metadata.name}')
  for node in $SPOT_NODES; do
    kubectl cordon "$node"
    log_warn "Cordoned $node (simulating capacity unavailable)"
  done
  
  # Step 4: Drain spot nodes (simulate eviction)
  log_warn "Step 4: Simulating SPOT EVICTION (draining spot nodes)..."
  for node in $SPOT_NODES; do
    kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --force 2>/dev/null || true
    log_warn "Drained $node"
  done
  
  log_info "Waiting for pods to reschedule..."
  sleep 10
  
  # Step 5: Show fallback distribution
  log_info "Step 5: Pod distribution after spot eviction..."
  echo ""
  kubectl get pods -o wide | awk 'NR==1 || /spot-workload/' | column -t
  echo ""
  
  PENDING=$(kubectl get pods --field-selector=status.phase=Pending -o name | wc -l)
  RUNNING=$(kubectl get pods --field-selector=status.phase=Running -o name | wc -l)
  
  if [[ "$PENDING" -gt 0 ]]; then
    log_warn "Some pods are PENDING (simulating no fallback capacity)"
    log_info "In real Karpenter, these would trigger on-demand node provisioning"
  else
    log_ok "All pods rescheduled successfully!"
  fi
  
  log_ok "Running: ${RUNNING}, Pending: ${PENDING}"
  
  # Step 6: Simulate capacity recovery
  log_info "Step 6: Simulating SPOT CAPACITY RECOVERY..."
  for node in $SPOT_NODES; do
    kubectl uncordon "$node"
    log_ok "Uncordoned $node (spot capacity available)"
  done
  
  log_info "=== SIMULATION COMPLETE ==="
  echo ""
  log_info "Key Observations:"
  log_info "  1. Pods initially spread across spot nodes (preferred)"
  log_info "  2. When spot nodes drained, pods moved to on-demand"
  log_info "  3. If on-demand capacity insufficient, pods would be Pending"
  log_info "  4. Karpenter would automatically provision new nodes"
}

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────────────────────────

cleanup() {
  log_info "Deleting Kind cluster: ${CLUSTER_NAME}"
  kind delete cluster --name ${CLUSTER_NAME}
  rm -f /tmp/kind-spot-contention.yaml /tmp/spot-workload.yaml
  log_ok "Cleanup complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

main() {
  case "${1:-all}" in
    setup)
      setup
      ;;
    run)
      run_simulation
      ;;
    cleanup)
      cleanup
      ;;
    all)
      setup
      run_simulation
      echo ""
      read -p "Press Enter to cleanup..." 
      cleanup
      ;;
    *)
      echo "Usage: $0 [setup|run|cleanup|all]"
      exit 1
      ;;
  esac
}

main "$@"
