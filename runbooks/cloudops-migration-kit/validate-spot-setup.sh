#!/usr/bin/env bash
# validate-spot-setup.sh - Validate complete spot setup health on an AKS cluster
#
# Runs 6 validation checks to verify spot pools, nodes, labels, taints,
# autoscaler profile, and priority expander ConfigMap are correctly configured.
#
# Usage:
#   ./validate-spot-setup.sh [OPTIONS]
#
# Options:
#   --json        Output results as JSON (machine-readable)
#   --help, -h    Show this help
#
# Prerequisites:
#   1. Copy .env.example to .env and edit with your cluster details
#   2. Source .env: export $(cat .env | xargs)
#   3. Login to Azure: az login
#   4. kubectl context set to target cluster
#
# Exit codes:
#   0 = all checks pass
#   1 = one or more checks failed
#
# See README.md for full migration walkthrough.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

show_help() {
  sed -n '/^# Usage:/,/^# Exit/p' "$0" | sed 's/^# //' | sed 's/^#//'
}

# ── Validation state ─────────────────────────────────────────────
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
declare -a CHECK_RESULTS=()

record_check() {
  local name="$1" status="$2" detail="$3"
  ((TOTAL_CHECKS++)) || true
  if [[ "$status" == "PASS" ]]; then
    ((PASSED_CHECKS++)) || true
    log_ok "CHECK $TOTAL_CHECKS: $name — $detail"
  else
    ((FAILED_CHECKS++)) || true
    log_error "CHECK $TOTAL_CHECKS: $name — $detail"
  fi
  CHECK_RESULTS+=("{\"check\":\"$name\",\"status\":\"$status\",\"detail\":\"$detail\"}")
}

# ── Check 1: Spot pools exist and are Succeeded ─────────────────
check_spot_pools() {
  log_info "Check 1: Spot pool provisioning state..."
  for pool in "${SPOT_POOLS[@]}"; do
    if pool_exists "$pool"; then
      local state
      state=$(get_pool_provisioning_state "$pool")
      if [[ "$state" == "Succeeded" ]]; then
        record_check "Pool '$pool' provisioning" "PASS" "State: $state"
      else
        record_check "Pool '$pool' provisioning" "FAIL" "State: $state (expected Succeeded)"
      fi
    else
      record_check "Pool '$pool' exists" "FAIL" "Pool not found"
    fi
  done
}

# ── Check 2: Spot nodes are Ready ───────────────────────────────
check_nodes_ready() {
  log_info "Check 2: Spot node readiness..."
  local spot_nodes
  spot_nodes=$(kubectl get nodes -l "kubernetes.azure.com/scalesetpriority=spot" \
    --no-headers 2>/dev/null || true)

  if [[ -z "$spot_nodes" ]]; then
    record_check "Spot nodes exist" "PASS" "No spot nodes running (pools may be scaled to zero — this is normal)"
    return
  fi

  local total=0
  local ready=0
  while IFS= read -r line; do
    ((total++)) || true
    if echo "$line" | grep -q " Ready "; then
      ((ready++)) || true
    fi
  done <<< "$spot_nodes"

  if [[ "$ready" -eq "$total" ]]; then
    record_check "Spot nodes ready" "PASS" "$ready/$total nodes Ready"
  else
    record_check "Spot nodes ready" "FAIL" "$ready/$total nodes Ready ($(( total - ready )) NotReady)"
  fi
}

# ── Check 3: Labels correct ─────────────────────────────────────
check_labels() {
  log_info "Check 3: Spot node labels..."
  local spot_nodes
  spot_nodes=$(kubectl get nodes -l "kubernetes.azure.com/scalesetpriority=spot" \
    -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)

  if [[ -z "$spot_nodes" ]]; then
    record_check "Spot node labels" "PASS" "No spot nodes to check (scaled to zero)"
    return
  fi

  local all_ok=true
  for node in $spot_nodes; do
    local workload_type
    workload_type=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.workload-type}' 2>/dev/null || echo "")
    local priority_label
    priority_label=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.priority}' 2>/dev/null || echo "")

    if [[ "$workload_type" != "spot" || "$priority_label" != "spot" ]]; then
      record_check "Labels on $node" "FAIL" "workload-type=$workload_type, priority=$priority_label (expected spot, spot)"
      all_ok=false
    fi
  done

  if [[ "$all_ok" == "true" ]]; then
    record_check "Spot node labels" "PASS" "All spot nodes have correct workload-type=spot, priority=spot"
  fi
}

# ── Check 4: Taint applied ──────────────────────────────────────
check_taints() {
  log_info "Check 4: Spot node taints..."
  local spot_nodes
  spot_nodes=$(kubectl get nodes -l "kubernetes.azure.com/scalesetpriority=spot" \
    -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)

  if [[ -z "$spot_nodes" ]]; then
    record_check "Spot node taints" "PASS" "No spot nodes to check (scaled to zero)"
    return
  fi

  local all_ok=true
  for node in $spot_nodes; do
    local taints
    taints=$(kubectl get node "$node" -o json 2>/dev/null | jq -r '.spec.taints[]? | "\(.key)=\(.value):\(.effect)"' 2>/dev/null || echo "")
    if echo "$taints" | grep -q "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"; then
      : # taint present
    else
      record_check "Taint on $node" "FAIL" "Missing kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
      all_ok=false
    fi
  done

  if [[ "$all_ok" == "true" ]]; then
    record_check "Spot node taints" "PASS" "All spot nodes have correct spot taint"
  fi
}

# ── Check 5: Autoscaler profile ─────────────────────────────────
check_autoscaler_profile() {
  log_info "Check 5: Autoscaler profile..."
  local profile
  profile=$(get_autoscaler_profile)

  if [[ -z "$profile" || "$profile" == "null" ]]; then
    record_check "Autoscaler profile" "FAIL" "Could not retrieve autoscaler profile"
    return
  fi

  local expander scan_interval scale_down_unready
  expander=$(echo "$profile" | jq -r '.expander // empty' 2>/dev/null || echo "")
  scan_interval=$(echo "$profile" | jq -r '.scanInterval // empty' 2>/dev/null || echo "")
  scale_down_unready=$(echo "$profile" | jq -r '.scaleDownUnreadyTime // empty' 2>/dev/null || echo "")

  if [[ "$expander" == "$AUTOSCALER_EXPANDER" ]]; then
    record_check "Autoscaler expander" "PASS" "expander=$expander"
  else
    record_check "Autoscaler expander" "FAIL" "expander=$expander (expected $AUTOSCALER_EXPANDER)"
  fi

  if [[ "$scan_interval" == "$AUTOSCALER_SCAN_INTERVAL" ]]; then
    record_check "Autoscaler scan interval" "PASS" "scan-interval=$scan_interval"
  else
    record_check "Autoscaler scan interval" "FAIL" "scan-interval=$scan_interval (expected $AUTOSCALER_SCAN_INTERVAL)"
  fi

  if [[ "$scale_down_unready" == "$AUTOSCALER_SCALE_DOWN_UNREADY" ]]; then
    record_check "Autoscaler scale-down-unready" "PASS" "scale-down-unready=$scale_down_unready"
  else
    record_check "Autoscaler scale-down-unready" "FAIL" "scale-down-unready=$scale_down_unready (expected $AUTOSCALER_SCALE_DOWN_UNREADY)"
  fi
}

# ── Check 6: Priority expander ConfigMap ─────────────────────────
check_priority_configmap() {
  log_info "Check 6: Priority expander ConfigMap..."
  if kubectl get configmap cluster-autoscaler-priority-expander -n kube-system &>/dev/null; then
    local priorities
    priorities=$(kubectl get configmap cluster-autoscaler-priority-expander -n kube-system \
      -o jsonpath='{.data.priorities}' 2>/dev/null || echo "")
    if [[ -n "$priorities" ]]; then
      record_check "Priority expander ConfigMap" "PASS" "ConfigMap exists in kube-system with priorities data"
    else
      record_check "Priority expander ConfigMap" "FAIL" "ConfigMap exists but 'priorities' data is empty"
    fi
  else
    record_check "Priority expander ConfigMap" "FAIL" "ConfigMap not found in kube-system"
  fi
}

# ── Main ─────────────────────────────────────────────────────────

main() {
  parse_common_args "$@"

  print_summary_header "Validate Spot Setup"

  # Preflight (minimal — validation itself checks most things)
  check_az_cli
  check_kubectl
  check_az_logged_in
  check_subscription

  # Run all checks
  check_spot_pools
  check_nodes_ready
  check_labels
  check_taints
  check_autoscaler_profile
  check_priority_configmap

  # Summary
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  Validation Summary${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo -e "  Total checks:  $TOTAL_CHECKS"
  echo -e "  Passed:        ${GREEN}$PASSED_CHECKS${NC}"
  echo -e "  Failed:        ${RED}$FAILED_CHECKS${NC}"
  echo ""

  # JSON output if requested
  if [[ "${JSON_OUTPUT:-false}" == "true" ]]; then
    local json_array
    json_array=$(printf '%s\n' "${CHECK_RESULTS[@]}" | jq -s '.')
    jq -n \
      --arg cluster "$CLUSTER_NAME" \
      --arg rg "$RESOURCE_GROUP" \
      --argjson total "$TOTAL_CHECKS" \
      --argjson passed "$PASSED_CHECKS" \
      --argjson failed "$FAILED_CHECKS" \
      --argjson checks "$json_array" \
      '{
        cluster: $cluster,
        resource_group: $rg,
        total_checks: $total,
        passed: $passed,
        failed: $failed,
        checks: $checks
      }'
  fi

  if [[ "$FAILED_CHECKS" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
