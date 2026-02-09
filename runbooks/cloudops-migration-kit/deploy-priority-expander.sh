#!/usr/bin/env bash
# deploy-priority-expander.sh - Deploy priority expander ConfigMap to AKS cluster
#
# Generates and applies the cluster-autoscaler-priority-expander ConfigMap to
# kube-system namespace. The ConfigMap tells the autoscaler which node pools to
# prefer when scaling up (lower priority number = preferred first).
#
# Usage:
#   ./deploy-priority-expander.sh [OPTIONS]
#
# Options:
#   --dry-run     Print ConfigMap YAML without applying
#   --yes, -y     Skip confirmation prompts
#   --help, -h    Show this help
#
# Prerequisites:
#   1. Copy .env.example to .env and edit with your cluster details
#   2. Source .env: export $(cat .env | xargs)
#   3. Login to Azure: az login
#   4. kubectl context set to target cluster:
#      az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME
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

# ── Generate priority expander ConfigMap YAML ────────────────────
# Groups pools by priority weight and generates regex-matched entries.
#
# DESIGN DECISION: Uses regex wildcards (.*poolname.*) to match node pool
# group names as they appear to the cluster autoscaler. This matches the
# Terraform template pattern in templates/priority-expander-data.tpl.
# The autoscaler sees node groups as "aks-poolname-12345678-vmss", so
# .*poolname.* correctly captures these.
generate_configmap() {
  # Collect unique priorities and sort them
  local -A priority_pools=()
  for pool in "${SPOT_POOLS[@]}"; do
    local pri="${POOL_PRIORITY[$pool]}"
    if [[ -n "${priority_pools[$pri]:-}" ]]; then
      priority_pools[$pri]="${priority_pools[$pri]}|${pool}"
    else
      priority_pools[$pri]="$pool"
    fi
  done

  # Add standard and system pools
  local std_pri="${POOL_PRIORITY[$STANDARD_POOL]}"
  if [[ -n "${priority_pools[$std_pri]:-}" ]]; then
    priority_pools[$std_pri]="${priority_pools[$std_pri]}|${STANDARD_POOL}"
  else
    priority_pools[$std_pri]="$STANDARD_POOL"
  fi

  local sys_pri="${POOL_PRIORITY[$SYSTEM_POOL]}"
  if [[ -n "${priority_pools[$sys_pri]:-}" ]]; then
    priority_pools[$sys_pri]="${priority_pools[$sys_pri]}|${SYSTEM_POOL}"
  else
    priority_pools[$sys_pri]="$SYSTEM_POOL"
  fi

  # Build the priorities data block
  local priorities_data=""
  # Sort priority keys numerically
  local sorted_priorities
  sorted_priorities=$(echo "${!priority_pools[@]}" | tr ' ' '\n' | sort -n)

  for pri in $sorted_priorities; do
    priorities_data+="${pri}:"$'\n'
    IFS='|' read -ra pools <<< "${priority_pools[$pri]}"
    for pool in "${pools[@]}"; do
      priorities_data+="  - .*${pool}.*"$'\n'
    done
  done

  # Generate full ConfigMap YAML
  cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-priority-expander
  namespace: kube-system
  labels:
    app: cluster-autoscaler
    managed-by: az-migration
data:
  priorities: |
${priorities_data}
EOF
}

# ── Main ─────────────────────────────────────────────────────────

main() {
  parse_common_args "$@"

  print_summary_header "Deploy Priority Expander ConfigMap"

  # Display priority configuration
  log_info "Priority expander configuration:"
  echo ""
  printf "  %-8s %-16s %s\n" "WEIGHT" "POOL" "DESCRIPTION"
  printf "  %-8s %-16s %s\n" "──────" "────" "───────────"

  # Sort by priority weight for display
  for pool in "${SPOT_POOLS[@]}"; do
    local pri="${POOL_PRIORITY[$pool]}"
    local desc="spot"
    if [[ "$pri" == "5" ]]; then desc="spot (memory-optimized, low eviction)"; fi
    printf "  %-8s %-16s %s\n" "$pri" "$pool" "$desc"
  done
  printf "  %-8s %-16s %s\n" "${POOL_PRIORITY[$STANDARD_POOL]}" "$STANDARD_POOL" "on-demand fallback"
  printf "  %-8s %-16s %s\n" "${POOL_PRIORITY[$SYSTEM_POOL]}" "$SYSTEM_POOL" "system (never for user workloads)"
  echo ""

  # Preflight
  run_preflight_with_kubectl

  # Generate ConfigMap
  log_info "Generated ConfigMap:"
  echo ""
  local configmap_yaml
  configmap_yaml=$(generate_configmap)
  echo "$configmap_yaml"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY-RUN: ConfigMap printed above but not applied"
    exit 0
  fi

  # Confirm
  confirm_action "Apply priority expander ConfigMap to cluster '$CLUSTER_NAME'?"

  # Apply
  log_info "Applying ConfigMap to kube-system namespace..."
  if echo "$configmap_yaml" | run_cmd kubectl apply -f -; then
    log_ok "Priority expander ConfigMap applied successfully"
  else
    log_error "Failed to apply ConfigMap"
    exit 1
  fi

  # Verify
  echo ""
  log_info "Verifying ConfigMap..."
  if kubectl get configmap cluster-autoscaler-priority-expander -n kube-system &>/dev/null; then
    log_ok "ConfigMap 'cluster-autoscaler-priority-expander' exists in kube-system"
    log_step "Contents:"
    kubectl get configmap cluster-autoscaler-priority-expander -n kube-system -o jsonpath='{.data.priorities}' 2>/dev/null
    echo ""
  else
    log_error "ConfigMap not found after apply"
    exit 1
  fi
}

main "$@"
