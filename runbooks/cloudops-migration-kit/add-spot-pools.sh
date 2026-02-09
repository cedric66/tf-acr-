#!/usr/bin/env bash
# add-spot-pools.sh - Add spot node pools to an existing AKS cluster
#
# Adds diversified spot node pools with autoscaling, zone pinning, and proper
# labels/taints. Idempotent: skips pools that already exist.
#
# Usage:
#   ./add-spot-pools.sh [OPTIONS]
#
# Options:
#   --dry-run     Print az commands without executing
#   --yes, -y     Skip confirmation prompts
#   --pool NAME   Add a single pool instead of all configured pools
#   --help, -h    Show this help
#
# Prerequisites:
#   1. Copy .env.example to .env and edit with your cluster details
#   2. Source .env: export $(cat .env | xargs)
#   3. Login to Azure: az login
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

  print_summary_header "Add Spot Node Pools"

  # Determine which pools to add
  local pools_to_add=()
  if [[ -n "$SINGLE_POOL" ]]; then
    # Validate the pool is in our config
    local found=false
    for p in "${SPOT_POOLS[@]}"; do
      if [[ "$p" == "$SINGLE_POOL" ]]; then found=true; break; fi
    done
    if [[ "$found" != "true" ]]; then
      log_error "Pool '$SINGLE_POOL' not found in SPOT_POOLS config: ${SPOT_POOLS[*]}"
      exit 1
    fi
    pools_to_add=("$SINGLE_POOL")
  else
    pools_to_add=("${SPOT_POOLS[@]}")
  fi

  # Display plan
  log_info "Pools to add: ${pools_to_add[*]}"
  echo ""
  printf "  %-16s %-22s %-8s %-10s %-10s\n" "POOL" "VM SIZE" "ZONE(S)" "MAX NODES" "PRIORITY"
  printf "  %-16s %-22s %-8s %-10s %-10s\n" "────" "───────" "───────" "─────────" "────────"
  for pool in "${pools_to_add[@]}"; do
    printf "  %-16s %-22s %-8s %-10s %-10s\n" \
      "$pool" \
      "${POOL_VM_SIZE[$pool]}" \
      "${POOL_ZONES[$pool]}" \
      "${POOL_MAX[$pool]}" \
      "${POOL_PRIORITY[$pool]}"
  done
  echo ""

  # Preflight
  run_preflight

  # Check for existing pools
  log_info "Checking existing node pools..."
  local existing_pools
  existing_pools=$(get_existing_pools)

  local skipped=0
  local to_create=()
  for pool in "${pools_to_add[@]}"; do
    if echo "$existing_pools" | grep -q "^${pool}$"; then
      log_warn "Pool '$pool' already exists — skipping (idempotent)"
      ((skipped++)) || true
    else
      to_create+=("$pool")
    fi
  done

  if [[ ${#to_create[@]} -eq 0 ]]; then
    log_ok "All requested pools already exist. Nothing to do."
    exit 0
  fi

  # Confirm
  confirm_action "Add ${#to_create[@]} spot pool(s) to cluster '$CLUSTER_NAME'?"

  # Create each pool
  local created=0
  local failed=0
  for pool in "${to_create[@]}"; do
    log_info "Creating spot pool: $pool"
    log_step "VM Size: ${POOL_VM_SIZE[$pool]}, Zone(s): ${POOL_ZONES[$pool]}, Max: ${POOL_MAX[$pool]}"

    # Convert comma-separated zones to space-separated for az CLI
    local zones_arg="${POOL_ZONES[$pool]//,/ }"

    if run_cmd az aks nodepool add \
      --resource-group "$RESOURCE_GROUP" \
      --cluster-name "$CLUSTER_NAME" \
      --name "$pool" \
      --node-count 0 \
      --node-vm-size "${POOL_VM_SIZE[$pool]}" \
      --zones $zones_arg \
      --min-count 0 \
      --max-count "${POOL_MAX[$pool]}" \
      --enable-cluster-autoscaling \
      --max-pods "$MAX_PODS" \
      --priority Spot \
      --spot-max-price "$SPOT_MAX_PRICE" \
      --eviction-policy Delete \
      --os-sku "$OS_SKU" \
      --node-osdisk-size "$OS_DISK_SIZE" \
      --labels \
        managed-by=az-migration \
        cost-optimization=spot-enabled \
        node-pool-type=user \
        workload-type=spot \
        priority=spot \
        vm-family="${POOL_VM_FAMILY[$pool]}" \
      --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"; then
      log_ok "Pool '$pool' created successfully"
      ((created++)) || true
    else
      log_error "Failed to create pool '$pool'"
      ((failed++)) || true
    fi
  done

  # Verify provisioning state
  if [[ "$DRY_RUN" != "true" && $created -gt 0 ]]; then
    echo ""
    log_info "Verifying provisioning state..."
    for pool in "${to_create[@]}"; do
      local state
      state=$(get_pool_provisioning_state "$pool" || echo "Unknown")
      if [[ "$state" == "Succeeded" ]]; then
        log_ok "Pool '$pool': $state"
      elif [[ "$state" == "Creating" ]]; then
        log_warn "Pool '$pool': $state (still provisioning — check back in a few minutes)"
      else
        log_error "Pool '$pool': $state"
      fi
    done
  fi

  # Summary
  echo ""
  log_info "Summary: ${created} created, ${skipped} skipped, ${failed} failed"
  if [[ $failed -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
