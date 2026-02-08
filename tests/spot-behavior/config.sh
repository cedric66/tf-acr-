#!/usr/bin/env bash
# config.sh - Cluster configuration for spot behavior tests
#
# CONFIGURATION:
# 1. Copy .env.example to .env
# 2. Edit .env with your cluster details
# 3. Load before running tests: source .env OR export $(cat .env | xargs)
# 4. See README.md for detailed setup instructions
#
# ALL variables use environment variables with fallback defaults.
# Defaults match terraform/modules/aks-spot-optimized/variables.tf

set -euo pipefail

# ── Cluster identity (customize via .env file) ───────────────────
CLUSTER_NAME="${CLUSTER_NAME:-aks-spot-prod}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aks-spot}"
NAMESPACE="${NAMESPACE:-robot-shop}"
LOCATION="${LOCATION:-australiaeast}"

# ── Node pool names (max 12 chars, lowercase alphanumeric) ───────
SYSTEM_POOL="${SYSTEM_POOL:-system}"
STANDARD_POOL="${STANDARD_POOL:-stdworkload}"

# Parse spot pools from env var (comma-separated) or use defaults
IFS=',' read -ra SPOT_POOLS <<< "${SPOT_POOLS:-spotgeneral1,spotmemory1,spotgeneral2,spotcompute,spotmemory2}"
ALL_SPOT_POOLS_CSV="${SPOT_POOLS:-spotgeneral1,spotmemory1,spotgeneral2,spotcompute,spotmemory2}"

# ── Default values for associative arrays ────────────────────────
# These are used if specific pool config is not provided via env vars
DEFAULT_VM_SIZE="Standard_D4s_v5"
DEFAULT_ZONES="1,2,3"
DEFAULT_PRIORITY="10"

# Pool-specific defaults (can be overridden via POOL_VM_SIZE_poolname, etc.)
declare -A DEFAULT_POOL_VM_SIZES=(
  [system]="Standard_D4s_v5"
  [stdworkload]="Standard_D4s_v5"
  [spotgeneral1]="Standard_D4s_v5"
  [spotmemory1]="Standard_E4s_v5"
  [spotgeneral2]="Standard_D8s_v5"
  [spotcompute]="Standard_F8s_v2"
  [spotmemory2]="Standard_E8s_v5"
)

declare -A DEFAULT_POOL_ZONES_MAP=(
  [system]="1,2,3"
  [stdworkload]="1,2"
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

# ── Build VM SKU mapping dynamically ─────────────────────────────
# Builds POOL_VM_SIZE array from env vars or defaults
declare -A POOL_VM_SIZE=()

# System and standard pools
POOL_VM_SIZE[$SYSTEM_POOL]="${POOL_VM_SIZE_system:-${DEFAULT_POOL_VM_SIZES[system]:-$DEFAULT_VM_SIZE}}"
POOL_VM_SIZE[$STANDARD_POOL]="${POOL_VM_SIZE_stdworkload:-${DEFAULT_POOL_VM_SIZES[stdworkload]:-$DEFAULT_VM_SIZE}}"

# Spot pools - dynamically from SPOT_POOLS array
for pool in "${SPOT_POOLS[@]}"; do
  # Check for env var POOL_VM_SIZE_poolname
  var_name="POOL_VM_SIZE_${pool}"
  # Use indirect expansion to get env var value, fall back to default for this pool, or generic default
  POOL_VM_SIZE[$pool]="${!var_name:-${DEFAULT_POOL_VM_SIZES[$pool]:-$DEFAULT_VM_SIZE}}"
done

# ── Build Zone mapping dynamically ───────────────────────────────
declare -A POOL_ZONES=()

POOL_ZONES[$SYSTEM_POOL]="${POOL_ZONES_system:-${DEFAULT_POOL_ZONES_MAP[system]:-$DEFAULT_ZONES}}"
POOL_ZONES[$STANDARD_POOL]="${POOL_ZONES_stdworkload:-${DEFAULT_POOL_ZONES_MAP[stdworkload]:-1,2}}"

for pool in "${SPOT_POOLS[@]}"; do
  var_name="POOL_ZONES_${pool}"
  POOL_ZONES[$pool]="${!var_name:-${DEFAULT_POOL_ZONES_MAP[$pool]:-1}}"
done

# ── Build Priority mapping dynamically ───────────────────────────
declare -A POOL_PRIORITY=()

POOL_PRIORITY[$SYSTEM_POOL]="${POOL_PRIORITY_system:-${DEFAULT_POOL_PRIORITIES[system]:-30}}"
POOL_PRIORITY[$STANDARD_POOL]="${POOL_PRIORITY_stdworkload:-${DEFAULT_POOL_PRIORITIES[stdworkload]:-20}}"

for pool in "${SPOT_POOLS[@]}"; do
  var_name="POOL_PRIORITY_${pool}"
  POOL_PRIORITY[$pool]="${!var_name:-${DEFAULT_POOL_PRIORITIES[$pool]:-$DEFAULT_PRIORITY}}"
done

# ── Build min/max node counts dynamically ────────────────────────
# Some tests (VMSS-004) expect POOL_MIN and POOL_MAX arrays
declare -A POOL_MIN=()
declare -A POOL_MAX=()

# Defaults
POOL_MIN[$SYSTEM_POOL]="${POOL_MIN_system:-3}"
POOL_MAX[$SYSTEM_POOL]="${POOL_MAX_system:-6}"
POOL_MIN[$STANDARD_POOL]="${POOL_MIN_stdworkload:-2}"
POOL_MAX[$STANDARD_POOL]="${POOL_MAX_stdworkload:-15}"

# Spot pools default: min=0 (can scale to zero), max=20
for pool in "${SPOT_POOLS[@]}"; do
  var_name_min="POOL_MIN_${pool}"
  var_name_max="POOL_MAX_${pool}"
  POOL_MIN[$pool]="${!var_name_min:-0}"
  POOL_MAX[$pool]="${!var_name_max:-20}"
done

# ── Robot-Shop services ──────────────────────────────────────────
# Override via: STATELESS_SERVICES="web,cart,catalogue" etc.
IFS=',' read -ra STATELESS_SERVICES <<< "${STATELESS_SERVICES:-web,cart,catalogue,user,payment,shipping,ratings,dispatch}"
IFS=',' read -ra STATEFUL_SERVICES <<< "${STATEFUL_SERVICES:-mongodb,mysql,redis,rabbitmq}"
ALL_SERVICES=("${STATELESS_SERVICES[@]}" "${STATEFUL_SERVICES[@]}")

# ── PDB configuration (all minAvailable:1) ───────────────────────
# Override via: PDB_SERVICES="web,cart,catalogue,mongodb"
IFS=',' read -ra PDB_SERVICES <<< "${PDB_SERVICES:-web,cart,catalogue,mongodb,mysql,redis,rabbitmq}"

# ── Timeouts (seconds) ──────────────────────────────────────────
TERMINATION_GRACE_PERIOD="${TERMINATION_GRACE_PERIOD:-35}"
PRESTOP_SLEEP="${PRESTOP_SLEEP:-25}"
AUTOSCALER_SCAN_INTERVAL="${AUTOSCALER_SCAN_INTERVAL:-20}"
GHOST_NODE_CLEANUP="${GHOST_NODE_CLEANUP:-180}"        # scale_down_unready = 3m
DESCHEDULER_INTERVAL="${DESCHEDULER_INTERVAL:-300}"    # 5m
POD_READY_TIMEOUT="${POD_READY_TIMEOUT:-120}"
NODE_READY_TIMEOUT="${NODE_READY_TIMEOUT:-300}"
DRAIN_TIMEOUT="${DRAIN_TIMEOUT:-60}"                   # max_graceful_termination_sec

# ── Results directory ────────────────────────────────────────────
RESULTS_DIR="${RESULTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/results}"
