#!/usr/bin/env bash
# config.sh - Centralized SKU configuration for spot migration
# Loads configuration from environment variables or defaults.
# Reference: .env.example and README.md

set -euo pipefail

# ── Cluster identity ────────────────────────────────────────────────────────
CLUSTER_NAME="${CLUSTER_NAME:-aks-spot-prod}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-aks-spot}"
LOCATION="${LOCATION:-australiaeast}"

# ── VM Family Selection by Pool ──────────────────────────────────────────────
# Memory-optimized pools (priority 5 - lowest eviction risk)
POOL_VM_SIZE_spotmemory1="${POOL_VM_SIZE_spotmemory1:-Standard_E4s_v5}"   # 4 vCPU, 32 GB
POOL_VM_SIZE_spotmemory2="${POOL_VM_SIZE_spotmemory2:-Standard_E8s_v5}"   # 8 vCPU, 64 GB

# General-purpose pools (priority 10)
POOL_VM_SIZE_spotgeneral1="${POOL_VM_SIZE_spotgeneral1:-Standard_D4s_v5}" # 4 vCPU, 16 GB
POOL_VM_SIZE_spotgeneral2="${POOL_VM_SIZE_spotgeneral2:-Standard_D8s_v5}" # 8 vCPU, 32 GB

# Compute-optimized pools (priority 10)
POOL_VM_SIZE_spotcompute="${POOL_VM_SIZE_spotcompute:-Standard_F8s_v2}"    # 8 vCPU, 16 GB

# ── Pool Sizing ─────────────────────────────────────────────────────────────
POOL_MAX_spotmemory1="${POOL_MAX_spotmemory1:-15}"
POOL_MAX_spotmemory2="${POOL_MAX_spotmemory2:-10}"
POOL_MAX_spotgeneral1="${POOL_MAX_spotgeneral1:-20}"
POOL_MAX_spotgeneral2="${POOL_MAX_spotgeneral2:-15}"
POOL_MAX_spotcompute="${POOL_MAX_spotcompute:-10}"

# ── Zones ───────────────────────────────────────────────────────────────────
POOL_ZONES_spotmemory1="${POOL_ZONES_spotmemory1:-1}"
POOL_ZONES_spotmemory2="${POOL_ZONES_spotmemory2:-2}"
POOL_ZONES_spotgeneral1="${POOL_ZONES_spotgeneral1:-1}"
POOL_ZONES_spotgeneral2="${POOL_ZONES_spotgeneral2:-2}"
POOL_ZONES_spotcompute="${POOL_ZONES_spotcompute:-3}"

# ── Build SKU Array Dynamically ─────────────────────────────────────────────
SPOT_SKUS=()
for pool in spotmemory1 spotmemory2 spotgeneral1 spotgeneral2 spotcompute; do
  var_name="POOL_VM_SIZE_${pool}"
  sku="${!var_name}"
  SPOT_SKUS+=("$sku")
done
