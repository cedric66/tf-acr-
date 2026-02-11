# Migration Guide: Converting an Existing AKS Cluster to Spot

**Audience:** Cloud Operations (Infrastructure) and Application/Workload Teams
**Purpose:** Step-by-step guide to safely add spot node pools to an existing AKS cluster and migrate workloads
**Last Updated:** 2026-02-11

> **This guide is for existing clusters.** If you are deploying a new cluster from scratch, see [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md).
>
> **Looking for a simpler approach?** See [MIGRATION_GUIDE_CONSERVATIVE.md](MIGRATION_GUIDE_CONSERVATIVE.md) for a streamlined 3-pool, 40% spot target guide (3-4 weeks vs 6-8 weeks).

---

## Table of Contents

1. [Overview](#1-overview)
2. [Pre-Migration Assessment](#2-pre-migration-assessment) (Cloud Ops)
   - 2.6 [Choosing the Right Number of Spot Pools](#26-choosing-the-right-number-of-spot-pools)
   - 2.7 [Sizing Nodes Per Pool](#27-sizing-nodes-per-pool)
   - 2.8 [Configurable SKU Selection](#28-configurable-sku-selection)
3. [Phase 1: Infrastructure Preparation](#3-phase-1-infrastructure-preparation) (Cloud Ops)
4. [Phase 2: Workload Audit](#4-phase-2-workload-audit) (App Teams + Cloud Ops)
5. [Phase 3: Pilot Migration](#5-phase-3-pilot-migration) (Both)
6. [Phase 4: Expand Spot Infrastructure](#6-phase-4-expand-spot-infrastructure) (Cloud Ops)
7. [Phase 5: Batch Workload Migration](#7-phase-5-batch-workload-migration) (App Teams)
8. [Phase 6: Steady State](#8-phase-6-steady-state) (Both)
9. [Rollback Procedures](#9-rollback-procedures)
10. [Communication Templates](#10-communication-templates)
11. [Appendix: Scripts](#11-appendix-scripts)

---

## 1. Overview

### What This Guide Covers

Converting an existing AKS cluster to use spot nodes involves two parallel workstreams:

```
Cloud Ops (Infrastructure)              App Teams (Workloads)
─────────────────────────               ─────────────────────
Phase 1: Add spot pools         →       Phase 2: Audit workloads
Phase 3: Pilot (joint)          ←→      Phase 3: Pilot (joint)
Phase 4: Expand spot infra      →       Phase 5: Batch migrate workloads
Phase 6: Steady state           ←→      Phase 6: Steady state
```

### Key Principles

- **No disruption to existing workloads** - Adding spot pools does not affect running pods
- **Opt-in per workload** - Only workloads with spot tolerations will schedule on spot nodes
- **Phased rollout** - Start with 1 pool and 1 workload, expand after validation
- **Reversible at every step** - Each phase has a documented rollback

### Timeline

| Phase | Duration | Who |
|-------|----------|-----|
| Pre-Migration Assessment | 1-2 days | Cloud Ops |
| Phase 1: Add canary spot pool | 1 day | Cloud Ops |
| Phase 2: Workload audit | 2-3 days | App Teams + Cloud Ops |
| Phase 3: Pilot (1-2 workloads) | 1-2 weeks | Both |
| Phase 4: Expand spot pools | 1 day | Cloud Ops |
| Phase 5: Batch migration | 2-4 weeks | App Teams |
| Phase 6: Steady state | Ongoing | Both |

---

## 2. Pre-Migration Assessment

> **Owner:** Cloud Ops / Platform Engineering

### 2.1 Cluster Compatibility Check

```bash
# Get cluster details
CLUSTER_NAME="<your-cluster>"
RESOURCE_GROUP="<your-rg>"

az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --query "{
    k8sVersion: kubernetesVersion,
    location: location,
    networkPlugin: networkProfile.networkPlugin,
    networkPolicy: networkProfile.networkPolicy,
    nodeResourceGroup: nodeResourceGroup,
    autoScalerProfile: autoScalerProfile
  }" -o table
```

**Requirements:**

| Requirement | Check | Notes |
|-------------|-------|-------|
| Kubernetes >= 1.28 | `az aks show --query kubernetesVersion` | Required for stable spot support |
| Cluster Autoscaler enabled | `az aks show --query autoScalerProfile` | Must be enabled cluster-wide |
| VMSS node pools (not AvailabilitySet) | `az aks nodepool list --query "[].type"` | Spot requires VMSS-backed pools |
| Network plugin: azure or kubenet | `az aks show --query networkProfile.networkPlugin` | Both supported |

### 2.2 Azure Quota and Capacity Check

> **Note:** For configurable SKU selection, see [Section 2.8: Configurable SKU Selection](#28-configurable-sku-selection).

```bash
# First, source your `scripts/migration/config.sh` (see Section 2.8)
source scripts/migration/config.sh

LOCATION=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query location -o tsv)

# Check VM quota for target VM families
echo "=== VM Quota Check ==="
az vm list-usage --location $LOCATION -o table | \
  grep -E "(Name|DSv5|ESv5|FSv2)"

# Check spot availability per configured SKU
echo "=== Spot SKU Availability ==="
for SKU in "${SPOT_SKUS[@]}"; do
  RESTRICTIONS=$(az vm list-skus --location "$LOCATION" --resource-type virtualMachines \
    --query "[?name=='${SKU}'].restrictions | [0]" -o json 2>/dev/null || echo '[]')
  if [ "$RESTRICTIONS" = "[]" ] || [ "$RESTRICTIONS" = "null" ]; then
    echo "  ✅ $SKU: Available"
  else
    echo "  ❌ $SKU: Restricted - $(echo "$RESTRICTIONS" | jq -r '.[].reasonCode' // 'Unknown')"
  fi
done

# Check available zones for first spot pool
echo "=== Zone Availability (for ${POOL_VM_SIZE_spotgeneral1}) ==="
az vm list-skus --location "$LOCATION" --resource-type virtualMachines \
  --query "[?name=='${POOL_VM_SIZE_spotgeneral1}'].locationInfo[0].zones | [0]" -o tsv
```

**Quota Planning:**

Each spot pool needs headroom. Calculate minimum quota needed:

```
Existing cluster vCPUs:     _____ (current usage)
+ System pool (3 nodes):    12 vCPUs (D4s_v5)
+ Standard pool (max 15):   60 vCPUs (D4s_v5)
+ Spot pools (5 pools):
  - spotmemory1 (max 15):   60 vCPUs (E4s_v5)
  - spotmemory2 (max 10):   80 vCPUs (E8s_v5)
  - spotgeneral1 (max 20):  80 vCPUs (D4s_v5)
  - spotgeneral2 (max 15):  120 vCPUs (D8s_v5)
  - spotcompute (max 10):   80 vCPUs (F8s_v2)
                            ─────
Total additional spot:      420 vCPUs (if all pools at max)
Recommended buffer:         50% of max = 210 vCPUs minimum
```

**Action:** If quota is insufficient, request increase before proceeding:
Azure Portal → Subscriptions → Usage + quotas → Request increase

### 2.3 Existing Autoscaler Profile Assessment

```bash
# Current autoscaler profile
az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --query autoScalerProfile -o json
```

**Compare current settings against spot-optimized values:**

| Setting | Spot-Optimized | Your Current | Impact of Change |
|---------|---------------|--------------|------------------|
| `expander` | `priority` | _____ | Changes pool selection logic |
| `scan-interval` | `20s` | _____ | More frequent scaling checks |
| `scale-down-unready` | `3m` | _____ | Faster ghost node cleanup |
| `max-node-provisioning-time` | `10m` | _____ | Faster stuck node timeout |
| `scale-down-delay-after-delete` | `10s` | _____ | Faster reaction to evictions |
| `scale-down-unneeded` | `5m` | _____ | Faster scale-down of idle nodes |
| `max-graceful-termination-sec` | `60` | _____ | Pod drain timeout |

**IMPORTANT:** Changing the autoscaler profile applies cluster-wide. If your existing workloads depend on specific autoscaler behavior (e.g., longer `scale-down-unneeded`), plan the change during a maintenance window.

### 2.4 Terraform State Assessment

**Scenario A: Cluster already managed by Terraform**

```bash
# Verify Terraform can see the cluster
cd terraform/environments/prod
terraform plan
# Expected: No changes (or known drift)
```

Add the spot pool resources to your existing Terraform configuration (see Phase 1).

**Scenario B: Cluster created via Azure Portal, CLI, or ARM template**

You have two options:

**Option B1: Import into Terraform (recommended for long-term management)**

```bash
# Import the existing cluster into Terraform state
terraform import module.aks.azurerm_kubernetes_cluster.main \
  /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster-name>

# Import existing node pools
terraform import module.aks.azurerm_kubernetes_cluster_node_pool.system \
  /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster-name>/agentPools/system

# Run plan to verify alignment
terraform plan
# Resolve any drift before adding spot pools
```

**Option B2: Add spot pools via Azure CLI only (faster, no Terraform)**

```bash
# First, configure `scripts/migration/config.sh` with your SKU preferences (see Section 2.8)
# Then source it before running commands
source scripts/migration/config.sh

# Add a spot pool directly via CLI
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --name spotgeneral1 \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --node-count 0 \
  --min-count 0 \
  --max-count 20 \
  --enable-cluster-autoscaler \
  --node-vm-size "${POOL_VM_SIZE_spotgeneral1:-Standard_D4s_v5}" \
  --zones "${POOL_ZONES_spotgeneral1:-1}" \
  --labels "workload-type=spot" "vm-family=general" "cost-optimization=spot-enabled" \
  --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule" \
  --no-wait
```

### 2.5 Pre-Migration Checklist

- [ ] Kubernetes version >= 1.28
- [ ] Cluster Autoscaler enabled
- [ ] Node pools use VMSS (not AvailabilitySet)
- [ ] VM quota sufficient for target spot pools
- [ ] Spot SKUs available in cluster region
- [ ] Availability zones verified
- [ ] Autoscaler profile changes reviewed and scheduled
- [ ] Terraform state aligned (if using Terraform)
- [ ] Maintenance window scheduled for autoscaler profile change
- [ ] Stakeholders notified (app teams, SRE, management)

### 2.6 Choosing the Right Number of Spot Pools

> **Best Practice Sources:**
> - Azure: [Add an Azure Spot node pool to AKS](https://learn.microsoft.com/en-us/azure/aks/spot-node-pool)
> - Azure: [Scaling Safely with Spot on AKS (July 2025)](https://blog.aks.azure.com/2025/07/17/Scaling-safely-with-spot-on-aks)
> - AWS: [Best practices for EC2 Spot with EKS](https://repost.aws/knowledge-center/eks-spot-instance-best-practices)

#### Decision Framework

Both Azure and AWS recommend **multiple spot pools with different VM sizes** to reduce correlated eviction risk. The optimal number depends on your cluster size and availability requirements.

| Factor | 3 Pools | 5 Pools (Recommended) | 7+ Pools |
|--------|---------|----------------------|----------|
| **Cluster Size** | < 50 nodes | 50-200 nodes | > 200 nodes |
| **Workload Diversity** | Single workload type | Mixed workloads | Highly varied |
| **Cost Savings Target** | 40-50% | 50-70% | Marginal gains |
| **Operational Complexity** | Low | Medium | High |
| **Correlated Eviction Risk** | ~2-4% | ~0.3-0.8% | <0.5% |
| **VM Families** | D + E series | D + E + F series | Add Arm64, N-series |

#### Pool Count Decision Tree

```
START
  │
  ├─ Can you tolerate ~2-4% simultaneous eviction risk?
  │   ├─ YES → 3 pools (minimum viable diversification)
  │   └─ NO → Continue
  │
  ├─ Do you have 50+ nodes or mixed workload types?
  │   ├─ YES → 5 pools (recommended sweet spot)
  │   └─ NO → 3 pools
  │
  └─ Do you have >200 nodes or extreme availability requirements?
      ├─ YES → 7+ pools (consider adding Arm64, N-series for GPU)
      └─ NO → 5 pools
```

#### VM Family Selection Strategy

Based on [Azure AKS Team Blog (July 2025)](https://blog.aks.azure.com/2025/07/17/Scaling-safely-with-spot-on-aks) and [EC2 Spot best practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html):

**Primary Families (x86) - Recommended for most deployments:**
- **D-series (general)**: Standard_D4s_v5, Standard_D8s_v5 - Baseline workloads
- **E-series (memory)**: Standard_E4s_v5, Standard_E8s_v5 - **Lower eviction risk** (historically)
- **F-series (compute)**: Standard_F8s_v2 - Compute-intensive workloads

**Secondary Families (for 7+ pools or specialized workloads):**
- **Arm64**: D4ps_v5, D8ps_v5 - Architecture diversification
- **N-series**: GPU workloads if applicable

**Key Rule:** Each pool = 1 VM family + 1 Zone (maximum diversification)

> **Why memory pools get priority:** Azure data shows E-series has the lowest historical eviction rates. Place them at priority tier 5 (highest preference) in your Priority Expander configuration.

### 2.7 Sizing Nodes Per Pool

> **Best Practice Sources:**
> - Azure: [AKS Cost Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices-cost)
> - Azure: [AKS Capacity Planning](https://learn.microsoft.com/en-us/azure/aks/upgrade-capacity-cost-planning)
> - AWS: [Best practices for Amazon EC2 Spot](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)

Per-pool sizing should balance three competing goals:
1. **Capacity headroom** for autoscaler during evictions
2. **Quota efficiency** (don't over-provision unused quota)
3. **Cost optimization** (maximize spot usage without over-buying)

#### Step 1: Calculate Baseline Capacity

**First, determine your total workload requirements:**

```bash
# Calculate total vCPU requests across all namespaces (memory calculation excluded)
kubectl get deployments -A -o json | jq -r '
  .items[] |
  select((.spec.template.spec.tolerations // []) | any(.key == "kubernetes.azure.com/scalesetpriority")) |
  {
    name: .metadata.name,
    namespace: .metadata.namespace,
    replicas: .spec.replicas,
    cpu: (.spec.template.spec.containers | map(.resources.requests.cpu // "0") | map(if endswith("m") then (rtrimstr("m") | tonumber / 1000) else tonumber end) | add)
  }
' | jq -s '
  # Note: Memory calculation requires complex unit conversion (Mi, Gi, M, G) and is out of scope for this quick check.
  "Total vCPU (approximate): \([.[] | .replicas * .cpu] | add // 0)"
'
```

The script outputs your cluster's **actual total vCPU baseline** — the sum of CPU requests × replica count across all spot-tolerant deployments. Use this number as your "Total vCPU needed" in the table below. The table shows example values; replace them with your own.

| Metric | How to Calculate | Example (replace with yours) |
|--------|------------------|---------|
| **Total vCPU needed** | Sum of all pod requests × replicas | 120 vCPUs |
| **Total memory needed** | Sum of all pod memory requests × replicas | 240 GB |
| **Peak buffer** | Add 20-30% for spikes | +36 vCPUs |
| **Baseline requirement** | Total + buffer | **156 vCPUs** |

> **Your calculation:** If the script output `X`, add 20–30% buffer → `X * 1.3` is your baseline requirement. Proceed to Step 2 with this number.

#### Step 2: Apply the 50% Spot Target Rule

**Industry best practice** from Azure and AWS guidance:

| Target Spot % | Spot Capacity Required | Standard Fallback |
|---------------|------------------------|-------------------|
| **50%** (conservative) | 50% of baseline | 50% on-demand |
| **70%** (recommended) | 70% of baseline | 30% on-demand |
| **90%** (aggressive) | 90% of baseline | 10% on-demand |

**For a 156 vCPU baseline with 70% spot target:**
- Spot capacity needed: ~110 vCPUs
- Standard fallback: ~46 vCPUs

#### Step 3: Distribute Across Pools Using Priority Weights

**Priority Tier Approach** (from your current architecture):

| Priority | Pool Type | % of Spot Capacity | Example Allocation |
|----------|-----------|-------------------|-------------------|
| **5** | Memory-optimized (E-series) | 40% | 44 vCPUs → 11×E4s_v5 + 3×E8s_v5 |
| **10** | General (D-series) | 40% | 44 vCPUs → 11×D4s_v5 + 2×D8s_v5 |
| **10** | Compute (F-series) | 20% | 22 vCPUs → 3×F8s_v2 |

#### Step 4: Set Min/Max Per Pool

**Formula:** `max_count = ceil(pool_vcpus / vm_size_vcpus × 1.5)`

The `1.5` multiplier provides:
- Headroom for autoscaler reaction time (20s scan interval)
- Buffer for regional capacity constraints
- Room for workload growth

**Example calculation for spotmemory1 (E4s_v5 = 4 vCPU):**
```
max_count = ceil(44 / 4 × 1.5) = ceil(16.5) = 17
```

| Pool | VM Size | vCPUs | Target Max | Formula Result | Recommended Max |
|------|---------|-------|------------|----------------|-----------------|
| spotmemory1 | E4s_v5 | 4 | 44 vCPUs | ceil(44/4 × 1.5) | **17** |
| spotmemory2 | E8s_v5 | 8 | 44 vCPUs | ceil(44/8 × 1.5) | **9** |
| spotgeneral1 | D4s_v5 | 4 | 44 vCPUs | ceil(44/4 × 1.5) | **17** |
| spotgeneral2 | D8s_v5 | 8 | 22 vCPUs | ceil(22/8 × 1.5) | **5** |
| spotcompute | F8s_v2 | 8 | 22 vCPUs | ceil(22/8 × 1.5) | **5** |

**All pools: `min_count = 0`** (let autoscaler drive scale-up from zero)

#### Step 5: Validate Against Quota

> See [`scripts/migration/validate-quota.sh`](../scripts/migration/validate-quota.sh) — Validates that your Azure VM quota can support the proposed spot pool sizing.
> Usage: `scripts/migration/validate-quota.sh`

#### Step 6: Standard Pool Sizing (Fallback Capacity)

**Rule:** Standard pool `max_count` = spot_max × (1 - spot_target%) / spot_target%

For 70% spot target:
```
standard_max = spot_max × 0.3 / 0.7 = spot_max × 0.43
```

| Metric | Calculation | Result |
|--------|-------------|--------|
| Spot max capacity | 17×4 + 9×8 + 17×4 + 5×8 + 5×8 | 264 vCPUs |
| Standard needed | 264 × 0.43 | **114 vCPUs** |
| Std pool max count (D4s_v5) | ceil(114 / 4) | **29 nodes** |

#### Quick Reference: Pool Sizing Cheat Sheet

| Cluster Size | Spot Pools | Per-Pool Max Range | Standard Max |
|--------------|------------|-------------------|--------------|
| Small (<50 nodes) | 3 | 5-10 nodes | 10-15 |
| Medium (50-200) | 5 | 10-20 nodes | 20-30 |
| Large (>200) | 7+ | 15-30 nodes | 40-60 |

**Adjustment factors:**
- Multiply by **1.5×** for bursty workloads
- Multiply by **0.7×** for steady-state/batch workloads
- Add **+5 nodes** per pool if running in capacity-constrained regions

### 2.8 Configurable SKU Selection

> **Best Practice Sources:**
> - Azure: [VMSS Instance Mix Overview](https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/instance-mix-overview)
> - Azure: [AKS Performance and Scaling Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices-performance-scale)
> - AWS: [EKS Managed Node Groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html)

#### Problem: Hardcoded Values Limit Portability

The migration guide previously contained hardcoded SKUs. This causes issues when:
- Target region has different SKUs available
- Quota constraints require different VM families
- Organizational standards mandate specific SKUs
- Testing in regions with limited spot availability

#### Solution: Environment-Based Configuration

**Create a centralized `config.sh` pattern:**

> See [`scripts/migration/config.sh`](../scripts/migration/config.sh) — Centralized configuration for cluster identity and VM SKU selection.
> Usage: `source scripts/migration/config.sh`

#### Updated Quota Check Script

> See [`scripts/migration/check-spot-availability.sh`](../scripts/migration/check-spot-availability.sh) — Validates that the configured spot SKUs are available in your target Azure region.
> Usage: `scripts/migration/check-spot-availability.sh`

#### Region-Specific SKU Recommendations

| Region | Recommended Spot SKUs | Alternatives If Restricted |
|--------|----------------------|---------------------------|
| **australiaeast** | D4s_v5, E4s_v5, F8s_v2 | D4ps_v5 (Arm64), D2s_v5 |
| **eastus** | D4s_v5, E4s_v5, F8s_v2 | D4as_v5, E4as_v5 |
| **westeurope** | D4s_v5, E4s_v5, F8s_v2 | D2s_v5, E2s_v5 |
| **southeastasia** | D2s_v5, E2s_v5, F4s_v2 | D4s_v3 (older gen) |
| **uksouth** | D4s_v5, E4s_v5, F8s_v2 | D4as_v5, E4as_v5 |

> **Note:** See [Azure Well-Architected Framework for AKS](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-kubernetes-service) for regional availability considerations.

---

## 3. Phase 1: Infrastructure Preparation

> **Owner:** Cloud Ops / Platform Engineering
> **Duration:** 1 day
> **Risk:** LOW - Adding a pool does not affect existing workloads

### 3.1 Update Autoscaler Profile

**This step changes cluster-wide autoscaler behavior. Schedule during a maintenance window.**

**Via Terraform:**

```hcl
# Add to your AKS cluster resource or module call
auto_scaler_profile {
  expander                      = "priority"
  scan_interval                 = "20s"
  scale_down_delay_after_delete = "10s"
  scale_down_unready            = "3m"
  scale_down_unneeded           = "5m"
  max_node_provisioning_time    = "10m"
  max_graceful_termination_sec  = 60
}
```

**Via Azure CLI:**

```bash
az aks update -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --cluster-autoscaler-profile \
    expander=priority \
    scan-interval=20s \
    scale-down-delay-after-delete=10s \
    scale-down-unready=3m \
    scale-down-unneeded=5m \
    max-node-provisioning-time=10m \
    max-graceful-termination-sec=60
```

**Verify:**

```bash
az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --query autoScalerProfile -o table
```

### 3.2 Add Canary Spot Pool (1 pool only)

Start with a single spot pool to validate behavior before adding all 5.

**Via Terraform:**

> **Tip:** For production use, define VM sizes as variables in your `variables.tf` to match the configurable approach in Section 2.8. Example: `vm_size = var.spot_pools["spotgeneral1"].vm_size`

```hcl
variable "spot_vm_size_general1" {
  description = "VM size for spotgeneral1 pool"
  type        = string
  default     = "Standard_D4s_v5"  # Override via tfvars or environment
}

resource "azurerm_kubernetes_cluster_node_pool" "spotgeneral1" {
  name                  = "spotgeneral1"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size              = var.spot_vm_size_general1
  priority             = "Spot"
  eviction_policy      = "Delete"
  spot_max_price       = -1

  enable_auto_scaling  = true
  min_count            = 0
  max_count            = 5    # Start small for canary
  node_count           = 0

  zones                = [1]

  node_labels = {
    "workload-type"      = "spot"
    "vm-family"          = "general"
    "cost-optimization"  = "spot-enabled"
    "managed-by"         = "terraform"
  }

  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  tags = {
    Environment = "prod"
    Phase       = "spot-canary"
  }
}
```

**Via Azure CLI:**

```bash
# First, source your `scripts/migration/config.sh` for configurable SKUs (see Section 2.8)
source scripts/migration/config.sh

az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --name spotgeneral1 \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --node-count 0 \
  --min-count 0 \
  --max-count 5 \
  --enable-cluster-autoscaler \
  --node-vm-size "${POOL_VM_SIZE_spotgeneral1}" \
  --zones "${POOL_ZONES_spotgeneral1:-1}" \
  --labels workload-type=spot vm-family=general cost-optimization=spot-enabled \
  --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
```

### 3.3 Deploy Priority Expander ConfigMap

The Priority Expander tells the autoscaler which pools to prefer. Without it, the autoscaler defaults to random selection.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-priority-expander
  namespace: kube-system
data:
  priorities: |
    10:
      - .*spotgeneral1.*
    20:
      - .*stdworkload.*
    30:
      - .*system.*
EOF
```

**Note:** Only include pool `spotgeneral1` for now. We'll update this in Phase 4 when adding more pools.

### 3.4 Verify Phase 1

```bash
# Canary pool exists
az aks nodepool show -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --nodepool-name spotgeneral1 \
  --query "{priority:scaleSetPriority, vmSize:vmSize, minCount:minCount, maxCount:maxCount}" \
  -o table

# Priority Expander deployed
kubectl get configmap cluster-autoscaler-priority-expander -n kube-system -o yaml

# Autoscaler recognizes the pool
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50 | \
  grep -i "spotgeneral1"

# Existing workloads unaffected
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded | \
  grep -v "Completed"
# Expected: No unexpected pending/failed pods
```

**Phase 1 Exit Criteria:**
- [ ] Canary spot pool created and visible in `kubectl get nodes` (will show 0 nodes until workloads request spot)
- [ ] Priority Expander ConfigMap deployed
- [ ] Autoscaler logs show new pool recognized
- [ ] Zero impact on existing workloads (no new pending pods, no restarts)

---

## 4. Phase 2: Workload Audit

> **Owner:** App Teams + Cloud Ops
> **Duration:** 2-3 days

### 4.1 Scan All Deployments for Spot Readiness

Run this audit script against each namespace to classify workloads:

> See [`scripts/migration/spot-readiness-audit.sh`](../scripts/migration/spot-readiness-audit.sh) — Scans deployments in a namespace and classifies them by spot-readiness based on replicas and health probes.
> Usage: `scripts/migration/spot-readiness-audit.sh <namespace>`

**Output Example:**

```
=== Classification ===

✅ READY  - web-frontend (6 replicas, has preStop)
✅ READY  - api-gateway (4 replicas, has preStop)
⚠️  MAYBE  - notification-svc (2 replicas, no preStop hook - add graceful shutdown)
⚠️  MAYBE  - auth-service (1 replica - increase before spot)
❌ NEVER  - postgres-primary (has PVC - stateful)
❌ NEVER  - redis-persistence (has PVC - stateful)
```

### 4.2 Classify Workloads

Organize audit results into three tiers:

| Tier | Criteria | Action |
|------|----------|--------|
| **Tier 1: Spot-Ready** | >= 3 replicas, preStop hook, readiness probe, no PVCs | Migrate in Phase 3 (pilot) or Phase 5 (batch) |
| **Tier 2: Needs Changes** | Missing preStop, < 3 replicas, or no readiness probe | App team fixes required before migration |
| **Tier 3: Never Spot** | Stateful (PVCs), compliance (PCI/HIPAA), singleton | Protect with hard anti-affinity (see 4.3) |

### 4.3 Protect Stateful Workloads (Tier 3)

Workloads that must NEVER schedule on spot nodes should have explicit anti-affinity. This protects against accidental toleration additions.

```yaml
# Add to stateful deployments that must stay on standard/system nodes
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.azure.com/scalesetpriority
              operator: NotIn
              values:
                - spot
```

**Apply to all Tier 3 workloads:**

```bash
# List all deployments with PVCs (likely stateful)
kubectl get deployments -A -o json | \
  jq -r '.items[] |
    select(.spec.template.spec.volumes // [] | any(.persistentVolumeClaim)) |
    "\(.metadata.namespace)/\(.metadata.name)"'
```

### 4.4 Tier 2 Remediation Checklist

For each Tier 2 workload, app teams should complete:

- [ ] **Increase replicas to >= 3** (minimum for spot HA)
- [ ] **Add preStop hook** with `sleep 25` for connection draining
- [ ] **Set terminationGracePeriodSeconds >= 35**
- [ ] **Add readiness probe** with `failureThreshold: 2`, `periodSeconds: 5`
- [ ] **Handle SIGTERM** in application code (see [DevOps Guide](DEVOPS_TEAM_GUIDE.md) for examples)
- [ ] **Create PodDisruptionBudget** with `minAvailable: 50%`
- [ ] **Test graceful shutdown** in dev environment

**Reference:** [DevOps Guide - Method 2: Full Optimization](DEVOPS_TEAM_GUIDE.md) for complete template

---

## 5. Phase 3: Pilot Migration

> **Owner:** Cloud Ops + App Teams (joint)
> **Duration:** 1-2 weeks
> **Goal:** Validate spot behavior with 1-2 low-risk workloads

### 5.1 Select Pilot Workloads

Choose 1-2 workloads from Tier 1 that are:
- Low business impact if degraded
- High replica count (6+) for best resilience demonstration
- Well-monitored (existing dashboards and alerts)
- Owned by a team willing to participate in the pilot

### 5.2 Migrate Pilot Workload

**Step 1: Backup current deployment**

```bash
NAMESPACE="<namespace>"
DEPLOYMENT="<deployment-name>"

kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o yaml > backup-$DEPLOYMENT.yaml
```

**Step 2: Add spot configuration**

```bash
# Apply spot toleration, affinity, topology spread, and PDB
# Use the full template from DevOps Guide Method 2
# Key additions:
kubectl patch deployment $DEPLOYMENT -n $NAMESPACE --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/tolerations/-",
    "value": {
      "key": "kubernetes.azure.com/scalesetpriority",
      "operator": "Equal",
      "value": "spot",
      "effect": "NoSchedule"
    }
  }
]'
```

Or apply a complete updated YAML (recommended for production):

```bash
# Edit backup with spot config from DevOps Guide Method 2
# Then apply
kubectl apply -f deployment-spot.yaml -n $NAMESPACE
```

**Step 3: Watch pods reschedule**

```bash
# Watch rollout
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=5m

# Verify pods on spot nodes
kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT -o wide

# Check which node type each pod is on
for pod in $(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT -o name); do
  node=$(kubectl get $pod -n $NAMESPACE -o jsonpath='{.spec.nodeName}')
  priority=$(kubectl get node $node -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}' 2>/dev/null || echo "unknown")
  echo "$pod → $node ($priority)"
done
```

### 5.3 Validate Pilot

**Test 1: Eviction resilience (non-destructive)**

```bash
# Drain a spot node to simulate eviction
SPOT_NODE=$(kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o name | head -1)
kubectl drain $SPOT_NODE --ignore-daemonsets --delete-emptydir-data --grace-period=60

# Watch pods reschedule
kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT -w

# Uncordon when done
kubectl uncordon $SPOT_NODE
```

**Test 2: Application health during eviction**

```bash
# Run continuous health check during drain test
while true; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$APP_ENDPOINT/health)
  echo "$(date +%H:%M:%S) $STATUS"
  sleep 1
done
```

### 5.4 Pilot Success Criteria

Monitor for 1-2 weeks. The pilot passes if ALL criteria are met:

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Application availability | >= 99.9% | Monitoring dashboard (uptime) |
| Error rate during eviction | < 0.1% | Application error rate metric |
| Pod reschedule time | < 60 seconds | `kubectl get events` timestamps |
| Zero customer-facing incidents | 0 incidents | Incident management system |
| Pods on spot nodes | >= 50% | `kubectl get pods -o wide` + node labels |
| PDB violations | 0 | `kubectl get pdb` |

### 5.5 Pilot Rollback (if needed)

```bash
# Restore original deployment
kubectl apply -f backup-$DEPLOYMENT.yaml -n $NAMESPACE

# Verify pods moved back to standard nodes
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE
kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT -o wide
```

---

## 6. Phase 4: Expand Spot Infrastructure

> **Owner:** Cloud Ops
> **Duration:** 1 day
> **Prerequisite:** Phase 3 pilot successful

### 6.1 Add Remaining Spot Pools

After successful pilot, add the remaining 4 spot pools for VM family diversity:

**Via Terraform** (add to node-pools configuration):

| Pool | VM Size | Zone | Priority Tier | Max Nodes |
|------|---------|------|---------------|-----------|
| spotmemory1 | Standard_E4s_v5 | 2 | 5 | 15 |
| spotmemory2 | Standard_E8s_v5 | 3 | 5 | 10 |
| spotgeneral2 | Standard_D8s_v5 | 2 | 10 | 15 |
| spotcompute | Standard_F8s_v2 | 3 | 10 | 10 |

**Via Azure CLI:**

```bash
# First, source your `scripts/migration/config.sh` for configurable SKUs (see Section 2.8)
source scripts/migration/config.sh

# Memory-optimized pools (priority 5 - preferred, lowest eviction risk)
az aks nodepool add -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --name spotmemory1 --priority Spot --eviction-policy Delete --spot-max-price -1 \
  --node-count 0 --min-count 0 --max-count "${POOL_MAX_spotmemory1:-15}" --enable-cluster-autoscaler \
  --node-vm-size "${POOL_VM_SIZE_spotmemory1}" --zones "${POOL_ZONES_spotmemory1:-2}" \
  --labels workload-type=spot vm-family=memory cost-optimization=spot-enabled \
  --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"

az aks nodepool add -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --name spotmemory2 --priority Spot --eviction-policy Delete --spot-max-price -1 \
  --node-count 0 --min-count 0 --max-count "${POOL_MAX_spotmemory2:-10}" --enable-cluster-autoscaler \
  --node-vm-size "${POOL_VM_SIZE_spotmemory2}" --zones "${POOL_ZONES_spotmemory2:-3}" \
  --labels workload-type=spot vm-family=memory cost-optimization=spot-enabled \
  --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"

# General/compute pools (priority 10)
az aks nodepool add -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --name spotgeneral2 --priority Spot --eviction-policy Delete --spot-max-price -1 \
  --node-count 0 --min-count 0 --max-count "${POOL_MAX_spotgeneral2:-15}" --enable-cluster-autoscaler \
  --node-vm-size "${POOL_VM_SIZE_spotgeneral2}" --zones "${POOL_ZONES_spotgeneral2:-2}" \
  --labels workload-type=spot vm-family=general cost-optimization=spot-enabled \
  --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"

az aks nodepool add -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --name spotcompute --priority Spot --eviction-policy Delete --spot-max-price -1 \
  --node-count 0 --min-count 0 --max-count "${POOL_MAX_spotcompute:-10}" --enable-cluster-autoscaler \
  --node-vm-size "${POOL_VM_SIZE_spotcompute}" --zones "${POOL_ZONES_spotcompute:-3}" \
  --labels workload-type=spot vm-family=compute cost-optimization=spot-enabled \
  --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
```

### 6.2 Update Priority Expander

Replace the canary ConfigMap with the full priority configuration:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-priority-expander
  namespace: kube-system
data:
  priorities: |
    5:
      - .*spotmemory1.*
      - .*spotmemory2.*
    10:
      - .*spotgeneral1.*
      - .*spotgeneral2.*
      - .*spotcompute.*
    20:
      - .*stdworkload.*
    30:
      - .*system.*
EOF
```

### 6.3 Install Descheduler

The Descheduler solves the "sticky fallback" problem - pods that land on standard nodes during eviction don't automatically return to spot when capacity recovers.

```bash
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler/
helm install descheduler descheduler/descheduler \
  --namespace kube-system \
  --set schedule="*/5 * * * *" \
  --set deschedulerPolicy.strategies.RemovePodsViolatingNodeAffinity.enabled=true \
  --set "deschedulerPolicy.strategies.RemovePodsViolatingNodeAffinity.params.nodeAffinityType[0]=preferredDuringSchedulingIgnoredDuringExecution"
```

### 6.4 Verify Phase 4

```bash
# All 5 spot pools exist
az aks nodepool list -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --query "[?scaleSetPriority=='Spot'].{name:name, vmSize:vmSize, minCount:minCount, maxCount:maxCount}" \
  -o table

# Priority Expander has all pools
kubectl get cm cluster-autoscaler-priority-expander -n kube-system -o yaml

# Descheduler running
kubectl get pods -n kube-system -l app=descheduler
kubectl get cronjob -n kube-system | grep descheduler

# Autoscaler recognizes all pools
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100 | \
  grep -E "spotmemory|spotgeneral|spotcompute"
```

---

## 7. Phase 5: Batch Workload Migration

> **Owner:** App Teams (with Cloud Ops support)
> **Duration:** 2-4 weeks

### 7.1 Migration Order

Migrate workloads in batches, ordered by risk:

| Batch | Workloads | Timeline | Rollback Window |
|-------|-----------|----------|-----------------|
| **Batch 1** | Dev/test namespaces | Week 1 | Immediate |
| **Batch 2** | Internal tools, batch jobs, CI runners | Week 2 | 24 hours |
| **Batch 3** | Production non-critical (monitoring, logging agents) | Week 3 | 48 hours |
| **Batch 4** | Production user-facing (APIs, frontends) | Week 4 | 1 week |

### 7.2 Per-Workload Migration Steps

For each deployment in the current batch:

**Step 1: Backup**

```bash
kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o yaml > backup-$DEPLOYMENT.yaml
```

**Step 2: Add spot configuration**

Add the following to the deployment spec (see [DevOps Guide Method 2](DEVOPS_TEAM_GUIDE.md) for full template):

```yaml
# Required: Allow scheduling on spot
tolerations:
  - key: kubernetes.azure.com/scalesetpriority
    operator: Equal
    value: spot
    effect: NoSchedule

# Required: Prefer spot, accept standard
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
            - key: kubernetes.azure.com/scalesetpriority
              operator: In
              values: [spot]

# Recommended: Spread across zones and node types
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: <app-name>

# Required if not present: Graceful shutdown
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 25"]
terminationGracePeriodSeconds: 35
```

**Step 3: Apply and verify**

```bash
kubectl apply -f deployment-spot.yaml -n $NAMESPACE
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=5m
```

**Step 4: Create PDB (if not exists)**

```bash
cat <<EOF | kubectl apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${DEPLOYMENT}-pdb
  namespace: $NAMESPACE
spec:
  minAvailable: 50%
  selector:
    matchLabels:
      app: $DEPLOYMENT
EOF
```

**Step 5: Verify pod placement**

```bash
# Check pods landed on spot nodes
for pod in $(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT -o name); do
  node=$(kubectl get $pod -n $NAMESPACE -o jsonpath='{.spec.nodeName}')
  priority=$(kubectl get node $node \
    -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}' 2>/dev/null)
  echo "$pod → $node ($priority)"
done
```

### 7.3 Batch Validation Criteria

Before proceeding to the next batch, verify:

- [ ] All workloads in current batch running on spot (or mixed spot/standard)
- [ ] No PDB violations
- [ ] Application error rate unchanged from baseline
- [ ] No new alerts triggered
- [ ] Team sign-off received

### 7.4 Per-Workload Rollback

If a specific workload has issues on spot:

```bash
# Restore original deployment (removes spot tolerations/affinity)
kubectl apply -f backup-$DEPLOYMENT.yaml -n $NAMESPACE

# Verify rollback
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE
kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT -o wide
# All pods should now be on standard nodes only
```

**Important:** Rolling back one workload does NOT affect other migrated workloads.

---

## 8. Phase 6: Steady State

> **Owner:** Both teams
> **Start:** After Phase 5 batch migration complete

### 8.1 Monitoring Dashboard Setup

Import Grafana dashboards from `monitoring/dashboards/`:

| Dashboard | Key Metrics |
|-----------|-------------|
| Spot Overview | Eviction rate, spot vs standard pod distribution, pending pods |
| Autoscaler Status | Scale-up/down events, pool-level node counts, unschedulable pods |

### 8.2 Weekly Review Cadence

**Schedule:** Weekly for first month, then biweekly

**Review Metrics:**

| Metric | Target | Action if Below |
|--------|--------|-----------------|
| Spot adoption % | >= 70% | Audit which workloads are still on standard |
| Eviction recovery time P95 | < 60s | Check autoscaler tuning |
| Monthly cost savings | >= 50% vs baseline | Review spot pricing, pool sizing |
| Availability | >= 99.9% | Review PDBs, replica counts |
| Pending pods (sustained) | 0 | Check autoscaler, capacity |

### 8.3 Cost Tracking

```bash
# Monthly spot vs standard cost comparison
# Check Azure Cost Management:
# Portal → Cost Management → Cost Analysis → Group by: Tag (kubernetes.azure.com/scalesetpriority)

# Or quick cluster-level check:
echo "=== Node Distribution ==="
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
POOL:.metadata.labels.agentpool,\
PRIORITY:.metadata.labels.kubernetes\\.azure\\.com/scalesetpriority,\
SIZE:.metadata.labels.node\\.kubernetes\\.io/instance-type

echo ""
echo "=== Summary ==="
echo "Spot nodes: $(kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot --no-headers | wc -l)"
echo "Standard nodes: $(kubectl get nodes -l priority=on-demand --no-headers | wc -l)"
echo "System nodes: $(kubectl get nodes -l agentpool=system --no-headers | wc -l)"
```

### 8.4 Ongoing Optimization

After 1 month of steady state:

- Review eviction patterns by VM SKU and zone (shift pools if needed)
- Adjust `max_count` per pool based on actual usage
- Consider adding more VM families if eviction rate is high for current SKUs
- Review descheduler effectiveness (are pods returning to spot?)

---

## 9. Rollback Procedures

### 9.1 Per-Workload Rollback

**When:** Single workload has issues on spot, other workloads are fine.

```bash
# Restore original deployment
kubectl apply -f backup-$DEPLOYMENT.yaml -n $NAMESPACE
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE
```

**Impact:** Only affects the single workload. Other spot workloads unaffected.

### 9.2 Pause All Spot Scheduling

**When:** Cluster-wide spot issues, need to stop new pods from going to spot while investigating.

```bash
# Cordon all spot nodes (prevents new pod scheduling)
kubectl cordon -l kubernetes.azure.com/scalesetpriority=spot

# Existing pods continue running on spot nodes
# New pods will only schedule on standard nodes

# When ready to resume:
kubectl uncordon -l kubernetes.azure.com/scalesetpriority=spot
```

**Impact:** Existing spot pods unaffected. New pods go to standard only.

### 9.3 Drain All Spot Nodes

**When:** Need to move ALL pods off spot immediately.

```bash
# Drain all spot nodes (moves pods to standard)
for node in $(kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o name); do
  kubectl drain $node --ignore-daemonsets --delete-emptydir-data --grace-period=60 &
done
wait

# Verify all pods on standard
kubectl get pods -A -o wide | grep -v "system\|kube-system" | head -20
```

**Impact:** All spot pods reschedule to standard. Temporary capacity pressure on standard pool (ensure `max_count` can absorb).

### 9.4 Remove All Spot Pools (Full Rollback)

**When:** Decision to abandon spot entirely.

```bash
# Step 1: Drain all spot nodes (see 9.3)

# Step 2: Remove Priority Expander
kubectl delete configmap cluster-autoscaler-priority-expander -n kube-system

# Step 3: Remove Descheduler
helm uninstall descheduler -n kube-system

# Step 4: Remove spot pools via Terraform or CLI
# Via CLI:
for pool in spotgeneral1 spotmemory1 spotgeneral2 spotmemory2 spotcompute; do
  az aks nodepool delete -g $RESOURCE_GROUP -n $CLUSTER_NAME \
    --nodepool-name $pool --no-wait
done

# Step 5: Revert autoscaler profile (optional)
az aks update -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --cluster-autoscaler-profile \
    expander=random \
    scale-down-unneeded=10m

# Step 6: Remove spot tolerations from workloads
# Apply backup YAMLs for each migrated workload
```

**Impact:** Full reversion to pre-migration state. All workloads on standard nodes.

---

## 10. Communication Templates

### 10.1 Announcement to App Teams (Pre-Migration)

```
Subject: [Action Required] AKS Spot Node Migration - Workload Assessment

Hi Team,

We're migrating our AKS cluster to use Azure Spot VMs to reduce cloud costs
by ~50%. This requires changes to your deployment configurations.

WHAT YOU NEED TO DO:
1. Review the workload audit results (attached)
2. For each Tier 2 workload: Add graceful shutdown handling
3. For each Tier 3 workload: Confirm it should NOT go to spot

TIMELINE:
- Week 1-2: Infrastructure preparation (no action from you)
- Week 3: Pilot with [pilot-workload-name]
- Week 4-6: Batch migration (your workloads)

RESOURCES:
- DevOps Guide: [link to DEVOPS_TEAM_GUIDE.md]
- Office Hours: Tuesday/Thursday 2-3 PM

No changes will be made to your workloads without your team's sign-off.

Questions? Reach out on #platform-engineering.
```

### 10.2 Per-Team Migration Notification

```
Subject: [Scheduled] Spot Migration for [namespace] - [date]

Hi [Team],

Your workloads in namespace [namespace] are scheduled for spot migration
on [date].

WORKLOADS BEING MIGRATED:
- [deployment-1] (Tier 1 - ready)
- [deployment-2] (Tier 1 - ready)
- [deployment-3] (Tier 2 - needs preStop hook, please add by [date])

NOT MIGRATING (Tier 3 - stateful):
- [database-deployment]

WHAT TO EXPECT:
- Rolling restart of migrated deployments (~2 min per deployment)
- Pods will prefer spot nodes but accept standard as fallback
- Zero expected downtime (PDBs ensure minimum availability)

ROLLBACK:
- Immediate rollback available if any issues detected
- Contact #platform-engineering or [on-call] for emergency rollback

Please confirm readiness by [date - 2 days].
```

### 10.3 Post-Migration Status Update

```
Subject: [Complete] Spot Migration Status - Week [N]

Migration Progress:
- Batch 1 (dev/test): ✅ Complete - 15 workloads migrated
- Batch 2 (internal): ✅ Complete - 8 workloads migrated
- Batch 3 (prod non-critical): 🔄 In progress - 5/12 migrated
- Batch 4 (prod user-facing): ⏳ Scheduled week [N+1]

Metrics:
- Spot adoption: 62% of eligible pods
- Cost savings this week: $X,XXX
- Evictions handled: XX (all recovered < 60s)
- Incidents: 0

Issues Found:
- [workload-X] needed longer preStop (fixed)
- [workload-Y] rolled back pending code changes (re-scheduled week [N+2])

Next Steps:
- Batch 3 completion by [date]
- Batch 4 kickoff [date]
```

---

## 11. Appendix: Scripts (Standalone)

The following scripts are now located in `scripts/migration/` to assist with cluster assessment and progress tracking.

### A. Full Cluster Spot Readiness Report

> See [`scripts/migration/cluster-spot-readiness.sh`](../scripts/migration/cluster-spot-readiness.sh) — Generates a comprehensive report of spot readiness across the entire cluster.
> Usage: `scripts/migration/cluster-spot-readiness.sh`

### B. Migration Progress Tracker

> See [`scripts/migration/migration-progress.sh`](../scripts/migration/migration-progress.sh) — Tracks the percentage of user pods currently running on spot nodes vs standard nodes.
> Usage: `scripts/migration/migration-progress.sh`

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| [Deployment Guide](DEPLOYMENT_GUIDE.md) | New cluster deployment (greenfield) |
| [DevOps Team Guide](DEVOPS_TEAM_GUIDE.md) | Application spot configuration templates |
| [SRE Operational Runbook](SRE_OPERATIONAL_RUNBOOK.md) | Incident response (Runbooks 1-10) |
| [Troubleshooting Guide](TROUBLESHOOTING_GUIDE.md) | Symptom-first diagnostics |
| [Spot Eviction Scenarios](SPOT_EVICITION_SCENARIOS.md) | Eviction behavior, sticky fallback |
| [Fleet Rollout Strategy](FLEET_ROLLOUT_STRATEGY.md) | Multi-cluster rollout at scale |

---

**Last Updated:** 2026-02-11
**Status:** Ready for use
