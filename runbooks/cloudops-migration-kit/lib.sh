#!/usr/bin/env bash
# lib.sh - Shared functions for Cloud Ops AKS Spot Migration Kit
#
# Provides: logging, preflight checks, dry-run support, az/kubectl helpers,
# user confirmation prompts.
#
# Source this file after config.sh in every script.
# See .env.example for configuration, README.md for usage.

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Logging ──────────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}[INFO]${NC}  $(date +%H:%M:%S) $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $(date +%H:%M:%S) $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date +%H:%M:%S) $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date +%H:%M:%S) $*" >&2; }
log_step()  { echo -e "  ${CYAN}➤${NC} $*"; }
log_debug() {
  if [[ "${LOG_LEVEL:-info}" == "debug" ]]; then
    echo -e "${BOLD}[DEBUG]${NC} $(date +%H:%M:%S) $*" >&2
  fi
}

# ── Dry-run wrapper ──────────────────────────────────────────────
# If DRY_RUN=true, prints the command instead of executing it.
# Usage: run_cmd az aks nodepool add --name pool1 ...
run_cmd() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    return 0
  fi
  log_debug "Running: $*"
  "$@"
}

# ── Confirmation prompt ──────────────────────────────────────────
# Prompts user for y/n confirmation. Skipped if AUTO_APPROVE=true.
# Usage: confirm_action "Delete 5 spot pools from cluster aks-prod?"
confirm_action() {
  local message="$1"
  if [[ "${AUTO_APPROVE:-false}" == "true" ]]; then
    log_debug "Auto-approved: $message"
    return 0
  fi
  echo ""
  echo -e "${BOLD}${message}${NC}"
  read -r -p "Continue? [y/N] " response
  case "$response" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) log_error "Aborted by user"; exit 1 ;;
  esac
}

# ── Preflight checks ────────────────────────────────────────────

check_az_cli() {
  if ! command -v az &>/dev/null; then
    log_error "Azure CLI (az) not found. Install: https://aka.ms/install-azure-cli"
    exit 1
  fi
  log_ok "Azure CLI found: $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null)"
}

check_kubectl() {
  if ! command -v kubectl &>/dev/null; then
    log_error "kubectl not found. Install: https://kubernetes.io/docs/tasks/tools/"
    exit 1
  fi
  log_ok "kubectl found: $(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' 2>/dev/null || echo 'unknown')"
}

check_az_logged_in() {
  if ! az account show &>/dev/null; then
    log_error "Not logged in to Azure CLI. Run: az login"
    exit 1
  fi
  local current_sub
  current_sub=$(az account show --query 'name' -o tsv 2>/dev/null)
  log_ok "Logged in to Azure subscription: $current_sub"
}

check_subscription() {
  if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
    local current_sub
    current_sub=$(az account show --query 'id' -o tsv 2>/dev/null)
    if [[ "$current_sub" != "$SUBSCRIPTION_ID" ]]; then
      log_warn "Current subscription ($current_sub) differs from SUBSCRIPTION_ID ($SUBSCRIPTION_ID)"
      log_info "Switching subscription..."
      run_cmd az account set --subscription "$SUBSCRIPTION_ID"
    fi
  fi
}

check_cluster_exists() {
  log_step "Checking cluster $CLUSTER_NAME exists in resource group $RESOURCE_GROUP..."
  if ! az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" &>/dev/null; then
    log_error "Cluster '$CLUSTER_NAME' not found in resource group '$RESOURCE_GROUP'"
    exit 1
  fi
  log_ok "Cluster '$CLUSTER_NAME' exists"
}

check_kubectl_context() {
  local current_context
  current_context=$(kubectl config current-context 2>/dev/null || echo "none")
  log_step "Current kubectl context: $current_context"

  # Get credentials if context doesn't match
  if [[ "$current_context" != *"$CLUSTER_NAME"* ]]; then
    log_warn "kubectl context may not match target cluster '$CLUSTER_NAME'"
    log_info "Run: az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
  fi
}

run_preflight() {
  log_info "Running preflight checks..."
  check_az_cli
  check_az_logged_in
  check_subscription
  check_cluster_exists
}

run_preflight_with_kubectl() {
  run_preflight
  check_kubectl
  check_kubectl_context
}

# ── az helpers ───────────────────────────────────────────────────

# Get list of existing node pool names in the cluster
get_existing_pools() {
  az aks nodepool list \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$CLUSTER_NAME" \
    --query '[].name' -o tsv 2>/dev/null
}

# Check if a specific pool exists
pool_exists() {
  local pool_name="$1"
  az aks nodepool show \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$CLUSTER_NAME" \
    --name "$pool_name" &>/dev/null
}

# Get current autoscaler profile as JSON
get_autoscaler_profile() {
  az aks show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --query 'autoScalerProfile' -o json 2>/dev/null
}

# Get provisioning state of a node pool
get_pool_provisioning_state() {
  local pool_name="$1"
  az aks nodepool show \
    --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$CLUSTER_NAME" \
    --name "$pool_name" \
    --query 'provisioningState' -o tsv 2>/dev/null
}

# ── CLI argument parsing helpers ─────────────────────────────────

# Parse common flags (--dry-run, --yes, --pool, --help, --json)
# Sets: DRY_RUN, AUTO_APPROVE, SINGLE_POOL, JSON_OUTPUT
# Usage: parse_common_args "$@"
parse_common_args() {
  SINGLE_POOL=""
  JSON_OUTPUT="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)  DRY_RUN="true"; shift ;;
      --yes|-y)   AUTO_APPROVE="true"; shift ;;
      --pool)     SINGLE_POOL="$2"; shift 2 ;;
      --json)     JSON_OUTPUT="true"; shift ;;
      --help|-h)  show_help; exit 0 ;;
      *)          log_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
  done

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY-RUN mode: commands will be printed but not executed"
  fi
}

# ── Summary output ───────────────────────────────────────────────

print_summary_header() {
  local title="$1"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  $title${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
  echo -e "  Cluster:        ${CYAN}$CLUSTER_NAME${NC}"
  echo -e "  Resource Group: ${CYAN}$RESOURCE_GROUP${NC}"
  echo -e "  Location:       ${CYAN}$LOCATION${NC}"
  echo ""
}
