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

# ── VM SKU mapping ───────────────────────────────────────────────
# Override via: POOL_VM_SIZE_system="Standard_D2s_v5" etc.
declare -A POOL_VM_SIZE=(
  [system]="${POOL_VM_SIZE_system:-Standard_D4s_v5}"
  [stdworkload]="${POOL_VM_SIZE_stdworkload:-Standard_D4s_v5}"
  [spotgeneral1]="${POOL_VM_SIZE_spotgeneral1:-Standard_D4s_v5}"
  [spotmemory1]="${POOL_VM_SIZE_spotmemory1:-Standard_E4s_v5}"
  [spotgeneral2]="${POOL_VM_SIZE_spotgeneral2:-Standard_D8s_v5}"
  [spotcompute]="${POOL_VM_SIZE_spotcompute:-Standard_F8s_v2}"
  [spotmemory2]="${POOL_VM_SIZE_spotmemory2:-Standard_E8s_v5}"
)

# ── Zone mapping ─────────────────────────────────────────────────
# Override via: POOL_ZONES_system="1,2,3" etc.
declare -A POOL_ZONES=(
  [system]="${POOL_ZONES_system:-1,2,3}"
  [stdworkload]="${POOL_ZONES_stdworkload:-1,2}"
  [spotgeneral1]="${POOL_ZONES_spotgeneral1:-1}"
  [spotmemory1]="${POOL_ZONES_spotmemory1:-2}"
  [spotgeneral2]="${POOL_ZONES_spotgeneral2:-2}"
  [spotcompute]="${POOL_ZONES_spotcompute:-3}"
  [spotmemory2]="${POOL_ZONES_spotmemory2:-3}"
)

# ── Priority expander weights (lower = higher priority) ──────────
# Override via: POOL_PRIORITY_system="30" etc.
declare -A POOL_PRIORITY=(
  [spotmemory1]="${POOL_PRIORITY_spotmemory1:-5}"
  [spotmemory2]="${POOL_PRIORITY_spotmemory2:-5}"
  [spotgeneral1]="${POOL_PRIORITY_spotgeneral1:-10}"
  [spotgeneral2]="${POOL_PRIORITY_spotgeneral2:-10}"
  [spotcompute]="${POOL_PRIORITY_spotcompute:-10}"
  [stdworkload]="${POOL_PRIORITY_stdworkload:-20}"
  [system]="${POOL_PRIORITY_system:-30}"
)

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
