#!/usr/bin/env bash
# config.sh - Cluster configuration for spot behavior tests
# Values must match terraform/modules/aks-spot-optimized/variables.tf defaults

set -euo pipefail

# ── Cluster identity ──────────────────────────────────────────────
CLUSTER_NAME="${CLUSTER_NAME:-aks-spot-prod}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aks-spot}"
NAMESPACE="${NAMESPACE:-robot-shop}"

# ── Node pool names (max 12 chars, lowercase alphanumeric) ───────
SYSTEM_POOL="system"
STANDARD_POOL="stdworkload"
SPOT_POOLS=("spotgeneral1" "spotmemory1" "spotgeneral2" "spotcompute" "spotmemory2")
ALL_SPOT_POOLS_CSV="spotgeneral1,spotmemory1,spotgeneral2,spotcompute,spotmemory2"

# ── VM SKU mapping ───────────────────────────────────────────────
declare -A POOL_VM_SIZE=(
  [system]="Standard_D4s_v5"
  [stdworkload]="Standard_D4s_v5"
  [spotgeneral1]="Standard_D4s_v5"
  [spotmemory1]="Standard_E4s_v5"
  [spotgeneral2]="Standard_D8s_v5"
  [spotcompute]="Standard_F8s_v2"
  [spotmemory2]="Standard_E8s_v5"
)

# ── Zone mapping ─────────────────────────────────────────────────
declare -A POOL_ZONES=(
  [system]="1,2,3"
  [stdworkload]="1,2"
  [spotgeneral1]="1"
  [spotmemory1]="2"
  [spotgeneral2]="2"
  [spotcompute]="3"
  [spotmemory2]="3"
)

# ── Priority expander weights (lower = higher priority) ──────────
declare -A POOL_PRIORITY=(
  [spotmemory1]="5"
  [spotmemory2]="5"
  [spotgeneral1]="10"
  [spotgeneral2]="10"
  [spotcompute]="10"
  [stdworkload]="20"
  [system]="30"
)

# ── Robot-Shop services ──────────────────────────────────────────
STATELESS_SERVICES=("web" "cart" "catalogue" "user" "payment" "shipping" "ratings" "dispatch")
STATEFUL_SERVICES=("mongodb" "mysql" "redis" "rabbitmq")
ALL_SERVICES=("${STATELESS_SERVICES[@]}" "${STATEFUL_SERVICES[@]}")

# ── PDB configuration (all minAvailable:1) ───────────────────────
PDB_SERVICES=("web" "cart" "catalogue" "mongodb" "mysql" "redis" "rabbitmq")

# ── Timeouts (seconds) ──────────────────────────────────────────
TERMINATION_GRACE_PERIOD=35
PRESTOP_SLEEP=25
AUTOSCALER_SCAN_INTERVAL=20
GHOST_NODE_CLEANUP=180        # scale_down_unready = 3m
DESCHEDULER_INTERVAL=300      # 5m
POD_READY_TIMEOUT=120
NODE_READY_TIMEOUT=300
DRAIN_TIMEOUT=60              # max_graceful_termination_sec

# ── Results directory ────────────────────────────────────────────
RESULTS_DIR="${RESULTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/results}"
