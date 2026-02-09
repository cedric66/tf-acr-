#!/usr/bin/env bash
# rollback-spot-pools.sh - Rollback: drain + delete spot pools + revert autoscaler
#
# Safely removes spot node pools from an AKS cluster by cordoning and draining
# nodes before deletion, then reverts the autoscaler to random expander.
#
# WARNING: This is a destructive operation. Pods on spot nodes will be evicted.
# Ensure standard/system pools have capacity to absorb displaced workloads.
#
# Usage:
#   ./rollback-spot-pools.sh [OPTIONS]
#
# Options:
#   --dry-run     Print commands without executing
#   --yes, -y     Skip confirmation prompts
#   --pool NAME   Rollback a single pool instead of all spot pools
#   --help, -h    Show this help
#
# Prerequisites:
#   1. Copy .env.example to .env and edit with your cluster details
#   2. Source .env: export $(cat .env | xargs)
#   3. Login to Azure: az login
#   4. kubectl context set to target cluster
#
# See README.md for full migration walkthrough.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

show_help() {
  sed -n '/^# Usage:/,/^# See/p' "$0" | sed 's/^# //' | sed 's/^#//'
}

# ── Main ─────────────────────────────────────────────────────────

main() {
  parse_common_args "$@"

  print_summary_header "Rollback Spot Pools"

  # Determine which pools to remove
  local pools_to_remove=()
  if [[ -n "$SINGLE_POOL" ]]; then
    pools_to_remove=("$SINGLE_POOL")
  else
    pools_to_remove=("${SPOT_POOLS[@]}")
  fi

  log_warn "This will REMOVE the following spot pools: ${pools_to_remove[*]}"
  log_warn "Pods on spot nodes will be drained and rescheduled to standard/system pools."
  echo ""

  # Preflight
  run_preflight_with_kubectl

  # Check which pools actually exist
  log_info "Checking which pools exist..."
  local existing_pools
  existing_pools=$(get_existing_pools)

  local to_remove=()
  local skipped=0
  for pool in "${pools_to_remove[@]}"; do
    if echo "$existing_pools" | grep -q "^${pool}$"; then
      to_remove+=("$pool")
    else
      log_warn "Pool '$pool' does not exist — skipping"
      ((skipped++)) || true
    fi
  done

  if [[ ${#to_remove[@]} -eq 0 ]]; then
    log_ok "No spot pools to remove."
  else
    # Double confirmation for destructive operation
    echo ""
    log_warn "DESTRUCTIVE OPERATION: About to drain and delete ${#to_remove[@]} pool(s)"
    confirm_action "Remove spot pools [${to_remove[*]}] from cluster '$CLUSTER_NAME'?"

    # Process each pool: cordon → drain → delete
    local deleted=0
    local failed=0
    for pool in "${to_remove[@]}"; do
      log_info "Processing pool: $pool"

      # Get nodes in this pool
      local nodes
      nodes=$(kubectl get nodes -l "agentpool=$pool" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)

      if [[ -n "$nodes" ]]; then
        # Cordon all nodes in pool
        for node in $nodes; do
          log_step "Cordoning node $node..."
          run_cmd kubectl cordon "$node" || true
        done

        # Drain all nodes in pool
        for node in $nodes; do
          log_step "Draining node $node (timeout: ${DRAIN_TIMEOUT}s)..."
          run_cmd kubectl drain "$node" \
            --ignore-daemonsets \
            --delete-emptydir-data \
            --timeout="${DRAIN_TIMEOUT}s" \
            --force 2>&1 || true
        done
      else
        log_step "No running nodes in pool '$pool' (may be scaled to zero)"
      fi

      # Delete the pool
      log_step "Deleting pool '$pool'..."
      if run_cmd az aks nodepool delete \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-name "$CLUSTER_NAME" \
        --name "$pool" \
        --no-wait; then
        log_ok "Pool '$pool' deletion initiated"
        ((deleted++)) || true
      else
        log_error "Failed to delete pool '$pool'"
        ((failed++)) || true
      fi
    done

    echo ""
    log_info "Pool removal: ${deleted} deleted, ${skipped} skipped, ${failed} failed"
  fi

  # Delete priority expander ConfigMap
  echo ""
  log_info "Removing priority expander ConfigMap..."
  if kubectl get configmap cluster-autoscaler-priority-expander -n kube-system &>/dev/null; then
    if run_cmd kubectl delete configmap cluster-autoscaler-priority-expander -n kube-system; then
      log_ok "Priority expander ConfigMap deleted"
    else
      log_warn "Failed to delete ConfigMap (may need manual cleanup)"
    fi
  else
    log_step "ConfigMap not found — nothing to delete"
  fi

  # Revert autoscaler to random expander
  echo ""
  log_info "Reverting autoscaler expander to 'random'..."
  if run_cmd az aks update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --auto-scaler-profile expander=random; then
    log_ok "Autoscaler reverted to 'random' expander"
  else
    log_error "Failed to revert autoscaler profile"
  fi

  # Verify pools are gone (skip in dry-run)
  if [[ "$DRY_RUN" != "true" ]]; then
    echo ""
    log_info "Verifying pool removal (pools delete asynchronously — some may still show)..."
    local remaining
    remaining=$(get_existing_pools)
    local still_present=0
    for pool in "${pools_to_remove[@]}"; do
      if echo "$remaining" | grep -q "^${pool}$"; then
        local state
        state=$(get_pool_provisioning_state "$pool" || echo "Deleting")
        log_warn "Pool '$pool' still present (state: $state) — deletion may be in progress"
        ((still_present++)) || true
      fi
    done
    if [[ "$still_present" -eq 0 ]]; then
      log_ok "All spot pools removed"
    fi
  fi

  echo ""
  log_ok "Rollback complete"
}

main "$@"
