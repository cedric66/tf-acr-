#!/usr/bin/env bash
# config.sh - Centralized configuration for Cloud Ops AKS Spot Migration Kit
#
# CONFIGURATION:
# 1. Copy .env.example to .env
# 2. Edit .env with your cluster details (at minimum: CLUSTER_NAME, RESOURCE_GROUP, LOCATION)
# 3. Source .env before running scripts: source .env OR export $(cat .env | xargs)
# 4. See README.md for detailed setup instructions
#
# ALL variables use environment variables with fallback defaults.
# Defaults match terraform/modules/aks-spot-optimized/variables.tf

set -euo pipefail

# ── Cluster identity (customize via .env file) ───────────────────
CLUSTER_NAME="${CLUSTER_NAME:-aks-spot-prod}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aks-spot}"
LOCATION="${LOCATION:-australiaeast}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"

# ── Node pool names ──────────────────────────────────────────────
SYSTEM_POOL="${SYSTEM_POOL:-system}"
STANDARD_POOL="${STANDARD_POOL:-stdworkload}"

# Parse spot pools from env var (comma-separated) or use defaults
IFS=',' read -ra SPOT_POOLS <<< "${SPOT_POOLS:-spotgeneral1,spotmemory1,spotgeneral2,spotcompute,spotmemory2}"

# ── Default values for associative arrays ────────────────────────
DEFAULT_VM_SIZE="Standard_D4s_v5"
DEFAULT_ZONES="1"
DEFAULT_PRIORITY="10"
DEFAULT_VM_FAMILY="general"

# Pool-specific defaults (match variables.tf exactly)
declare -A DEFAULT_POOL_VM_SIZES=(
  [spotgeneral1]="Standard_D4s_v5"
  [spotmemory1]="Standard_E4s_v5"
  [spotgeneral2]="Standard_D8s_v5"
  [spotcompute]="Standard_F8s_v2"
  [spotmemory2]="Standard_E8s_v5"
)

declare -A DEFAULT_POOL_ZONES_MAP=(
  [spotgeneral1]="1"
  [spotmemory1]="2"
  [spotgeneral2]="2"
  [spotcompute]="3"
  [spotmemory2]="3"
)

declare -A DEFAULT_POOL_PRIORITIES=(
  [system]="30"
  [stdworkload]="20"
  [spotgeneral1]="10"
  [spotgeneral2]="10"
  [spotcompute]="10"
  [spotmemory1]="5"
  [spotmemory2]="5"
)

declare -A DEFAULT_POOL_VM_FAMILIES=(
  [spotgeneral1]="general"
  [spotmemory1]="memory"
  [spotgeneral2]="general"
  [spotcompute]="compute"
  [spotmemory2]="memory"
)

declare -A DEFAULT_POOL_MAX=(
  [spotgeneral1]="20"
  [spotmemory1]="15"
  [spotgeneral2]="15"
  [spotcompute]="10"
  [spotmemory2]="10"
)

# ── Build VM SKU mapping dynamically ─────────────────────────────
declare -A POOL_VM_SIZE=()
for pool in "${SPOT_POOLS[@]}"; do
  var_name="POOL_VM_SIZE_${pool}"
  POOL_VM_SIZE[$pool]="${!var_name:-${DEFAULT_POOL_VM_SIZES[$pool]:-$DEFAULT_VM_SIZE}}"
done

# ── Build Zone mapping dynamically ───────────────────────────────
declare -A POOL_ZONES=()
for pool in "${SPOT_POOLS[@]}"; do
  var_name="POOL_ZONES_${pool}"
  POOL_ZONES[$pool]="${!var_name:-${DEFAULT_POOL_ZONES_MAP[$pool]:-$DEFAULT_ZONES}}"
done

# ── Build Priority mapping dynamically ───────────────────────────
declare -A POOL_PRIORITY=()
POOL_PRIORITY[$SYSTEM_POOL]="${POOL_PRIORITY_system:-${DEFAULT_POOL_PRIORITIES[system]:-30}}"
POOL_PRIORITY[$STANDARD_POOL]="${POOL_PRIORITY_stdworkload:-${DEFAULT_POOL_PRIORITIES[stdworkload]:-20}}"
for pool in "${SPOT_POOLS[@]}"; do
  var_name="POOL_PRIORITY_${pool}"
  POOL_PRIORITY[$pool]="${!var_name:-${DEFAULT_POOL_PRIORITIES[$pool]:-$DEFAULT_PRIORITY}}"
done

# ── Build VM Family mapping dynamically ──────────────────────────
declare -A POOL_VM_FAMILY=()
for pool in "${SPOT_POOLS[@]}"; do
  var_name="POOL_VM_FAMILY_${pool}"
  POOL_VM_FAMILY[$pool]="${!var_name:-${DEFAULT_POOL_VM_FAMILIES[$pool]:-$DEFAULT_VM_FAMILY}}"
done

# ── Build min/max node counts dynamically ────────────────────────
declare -A POOL_MIN=()
declare -A POOL_MAX=()
for pool in "${SPOT_POOLS[@]}"; do
  var_name_min="POOL_MIN_${pool}"
  var_name_max="POOL_MAX_${pool}"
  POOL_MIN[$pool]="${!var_name_min:-0}"
  POOL_MAX[$pool]="${!var_name_max:-${DEFAULT_POOL_MAX[$pool]:-20}}"
done

# ── Spot pool defaults ───────────────────────────────────────────
SPOT_MAX_PRICE="${SPOT_MAX_PRICE:--1}"
MAX_PODS="${MAX_PODS:-50}"
OS_SKU="${OS_SKU:-Ubuntu}"
OS_DISK_SIZE="${OS_DISK_SIZE:-128}"

# ── Autoscaler profile settings ─────────────────────────────────
AUTOSCALER_EXPANDER="${AUTOSCALER_EXPANDER:-priority}"
AUTOSCALER_SCAN_INTERVAL="${AUTOSCALER_SCAN_INTERVAL:-20s}"
AUTOSCALER_SCALE_DOWN_UNREADY="${AUTOSCALER_SCALE_DOWN_UNREADY:-3m}"
AUTOSCALER_SCALE_DOWN_UNNEEDED="${AUTOSCALER_SCALE_DOWN_UNNEEDED:-5m}"
AUTOSCALER_SCALE_DOWN_DELAY_AFTER_ADD="${AUTOSCALER_SCALE_DOWN_DELAY_AFTER_ADD:-10m}"
AUTOSCALER_SCALE_DOWN_DELAY_AFTER_DELETE="${AUTOSCALER_SCALE_DOWN_DELAY_AFTER_DELETE:-10s}"
AUTOSCALER_SCALE_DOWN_DELAY_AFTER_FAILURE="${AUTOSCALER_SCALE_DOWN_DELAY_AFTER_FAILURE:-3m}"
AUTOSCALER_SCALE_DOWN_UTILIZATION="${AUTOSCALER_SCALE_DOWN_UTILIZATION:-0.5}"
AUTOSCALER_MAX_GRACEFUL_TERMINATION="${AUTOSCALER_MAX_GRACEFUL_TERMINATION:-60}"
AUTOSCALER_MAX_NODE_PROVISIONING_TIME="${AUTOSCALER_MAX_NODE_PROVISIONING_TIME:-10m}"
AUTOSCALER_MAX_UNREADY_NODES="${AUTOSCALER_MAX_UNREADY_NODES:-3}"
AUTOSCALER_MAX_UNREADY_PERCENTAGE="${AUTOSCALER_MAX_UNREADY_PERCENTAGE:-45}"
AUTOSCALER_NEW_POD_SCALE_UP_DELAY="${AUTOSCALER_NEW_POD_SCALE_UP_DELAY:-0s}"
AUTOSCALER_BALANCE_SIMILAR="${AUTOSCALER_BALANCE_SIMILAR:-true}"
AUTOSCALER_SKIP_LOCAL_STORAGE="${AUTOSCALER_SKIP_LOCAL_STORAGE:-false}"
AUTOSCALER_SKIP_SYSTEM_PODS="${AUTOSCALER_SKIP_SYSTEM_PODS:-true}"

# ── Operational settings ─────────────────────────────────────────
DRY_RUN="${DRY_RUN:-false}"
DRAIN_TIMEOUT="${DRAIN_TIMEOUT:-60}"
LOG_LEVEL="${LOG_LEVEL:-info}"
