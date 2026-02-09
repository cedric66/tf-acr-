#!/usr/bin/env bash
# update-autoscaler-profile.sh - Update AKS cluster autoscaler to priority expander mode
#
# Configures the cluster autoscaler profile with settings optimized for spot
# instances and bursty workloads. Changes the expander to 'priority' mode so
# the autoscaler prefers cheaper spot pools over on-demand.
#
# Usage:
#   ./update-autoscaler-profile.sh [OPTIONS]
#
# Options:
#   --dry-run     Print az commands without executing
#   --yes, -y     Skip confirmation prompts
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

  print_summary_header "Update Autoscaler Profile"

  # Display planned settings
  log_info "Autoscaler profile settings to apply:"
  echo ""
  printf "  %-42s %s\n" "SETTING" "VALUE"
  printf "  %-42s %s\n" "───────" "─────"
  printf "  %-42s %s\n" "expander" "$AUTOSCALER_EXPANDER"
  printf "  %-42s %s\n" "scan-interval" "$AUTOSCALER_SCAN_INTERVAL"
  printf "  %-42s %s\n" "balance-similar-node-groups" "$AUTOSCALER_BALANCE_SIMILAR"
  printf "  %-42s %s\n" "max-graceful-termination-sec" "$AUTOSCALER_MAX_GRACEFUL_TERMINATION"
  printf "  %-42s %s\n" "max-node-provisioning-time" "$AUTOSCALER_MAX_NODE_PROVISIONING_TIME"
  printf "  %-42s %s\n" "max-unready-nodes" "$AUTOSCALER_MAX_UNREADY_NODES"
  printf "  %-42s %s\n" "max-unready-percentage" "$AUTOSCALER_MAX_UNREADY_PERCENTAGE"
  printf "  %-42s %s\n" "new-pod-scale-up-delay" "$AUTOSCALER_NEW_POD_SCALE_UP_DELAY"
  printf "  %-42s %s\n" "scale-down-delay-after-add" "$AUTOSCALER_SCALE_DOWN_DELAY_AFTER_ADD"
  printf "  %-42s %s\n" "scale-down-delay-after-delete" "$AUTOSCALER_SCALE_DOWN_DELAY_AFTER_DELETE"
  printf "  %-42s %s\n" "scale-down-delay-after-failure" "$AUTOSCALER_SCALE_DOWN_DELAY_AFTER_FAILURE"
  printf "  %-42s %s\n" "scale-down-unneeded" "$AUTOSCALER_SCALE_DOWN_UNNEEDED"
  printf "  %-42s %s\n" "scale-down-unready" "$AUTOSCALER_SCALE_DOWN_UNREADY"
  printf "  %-42s %s\n" "scale-down-utilization-threshold" "$AUTOSCALER_SCALE_DOWN_UTILIZATION"
  printf "  %-42s %s\n" "skip-nodes-with-local-storage" "$AUTOSCALER_SKIP_LOCAL_STORAGE"
  printf "  %-42s %s\n" "skip-nodes-with-system-pods" "$AUTOSCALER_SKIP_SYSTEM_PODS"
  echo ""

  # Preflight
  run_preflight

  # Capture current profile for reference
  if [[ "$DRY_RUN" != "true" ]]; then
    log_info "Current autoscaler profile (for rollback reference):"
    local current_profile
    current_profile=$(get_autoscaler_profile)
    echo "$current_profile" | jq . 2>/dev/null || echo "$current_profile"
    echo ""
  fi

  # Confirm
  confirm_action "Update autoscaler profile on cluster '$CLUSTER_NAME'?"

  # Apply autoscaler profile
  log_info "Applying autoscaler profile..."
  if run_cmd az aks update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --auto-scaler-profile \
      balance-similar-node-groups="$AUTOSCALER_BALANCE_SIMILAR" \
      expander="$AUTOSCALER_EXPANDER" \
      max-graceful-termination-sec="$AUTOSCALER_MAX_GRACEFUL_TERMINATION" \
      max-node-provisioning-time="$AUTOSCALER_MAX_NODE_PROVISIONING_TIME" \
      max-unready-nodes="$AUTOSCALER_MAX_UNREADY_NODES" \
      max-unready-percentage="$AUTOSCALER_MAX_UNREADY_PERCENTAGE" \
      new-pod-scale-up-delay="$AUTOSCALER_NEW_POD_SCALE_UP_DELAY" \
      scale-down-delay-after-add="$AUTOSCALER_SCALE_DOWN_DELAY_AFTER_ADD" \
      scale-down-delay-after-delete="$AUTOSCALER_SCALE_DOWN_DELAY_AFTER_DELETE" \
      scale-down-delay-after-failure="$AUTOSCALER_SCALE_DOWN_DELAY_AFTER_FAILURE" \
      scale-down-unneeded="$AUTOSCALER_SCALE_DOWN_UNNEEDED" \
      scale-down-unready="$AUTOSCALER_SCALE_DOWN_UNREADY" \
      scale-down-utilization-threshold="$AUTOSCALER_SCALE_DOWN_UTILIZATION" \
      scan-interval="$AUTOSCALER_SCAN_INTERVAL" \
      skip-nodes-with-local-storage="$AUTOSCALER_SKIP_LOCAL_STORAGE" \
      skip-nodes-with-system-pods="$AUTOSCALER_SKIP_SYSTEM_PODS"; then
    log_ok "Autoscaler profile updated successfully"
  else
    log_error "Failed to update autoscaler profile"
    exit 1
  fi

  # Verify
  if [[ "$DRY_RUN" != "true" ]]; then
    echo ""
    log_info "Verifying autoscaler profile..."
    local expander
    expander=$(az aks show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$CLUSTER_NAME" \
      --query 'autoScalerProfile.expander' -o tsv 2>/dev/null)
    if [[ "$expander" == "$AUTOSCALER_EXPANDER" ]]; then
      log_ok "Expander is set to '$expander'"
    else
      log_error "Expander is '$expander' (expected '$AUTOSCALER_EXPANDER')"
      exit 1
    fi
  fi
}

main "$@"
