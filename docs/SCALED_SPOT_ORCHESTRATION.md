# Scaled Spot Orchestration Guide

> **Version:** 1.0  
> **Created:** 2026-01-20  
> **Scope:** Managing 10-15 AKS Clusters with Spot Instances at Scale

---

## Karpenter/NAP Status (as of January 2026)

| Aspect | Status |
|--------|--------|
| **Availability** | ✅ **Generally Available** (since July 2025) |
| **Terraform Support** | azurerm 4.x+ (check your provider version) |
| **Required Networking** | Azure CNI Overlay + Cilium |
| **Unsupported** | Kubenet, Calico, Windows nodes, IPv6 |

> [!TIP]
> NAP is now GA! Enable it directly:
> ```bash
> az aks update -g <rg> -n <cluster> --node-provisioning-mode Auto
> ```

---

## Executive Summary

This document addresses the challenge of running **10-15 AKS clusters** in a single Azure region while efficiently utilizing **Spot VMs**. At this scale, clusters compete for the same Spot capacity, creating "thundering herd" scenarios during peak demand or regional capacity constraints.

The solution combines:
1. **Instance Diversity** - Spread workloads across multiple VM SKUs
2. **Regional Distribution** - Utilize multiple Availability Zones and regions
3. **Karpenter (NAP)** - Dynamic provisioning for automatic fallback
4. **Coordinated Scaling** - Staggered scaling to avoid capacity spikes

---

## Table of Contents

1. [The Contention Problem](#the-contention-problem)
2. [Scenario Analysis](#scenario-analysis)
3. [Solution Architecture](#solution-architecture)
4. [Karpenter Implementation](#karpenter-implementation)
5. [Fleet Management Strategies](#fleet-management-strategies)
6. [Testing & Simulation](#testing--simulation)

---

## The Contention Problem

### Why 10-15 Clusters Creates Unique Challenges

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Azure Region: West Europe                             │
│                                                                              │
│   ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐              │
│   │Cluster 1│ │Cluster 2│ │Cluster 3│ │Cluster 4│ │Cluster 5│  ...x15      │
│   └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘              │
│        │          │          │          │          │                       │
│        └──────────┴──────────┴──────────┴──────────┘                       │
│                              │                                              │
│                              ▼                                              │
│                    ┌─────────────────┐                                      │
│                    │  Azure Spot     │                                      │
│                    │  Capacity Pool  │ ◄── LIMITED CAPACITY                 │
│                    │  (D4s_v5)       │                                      │
│                    └─────────────────┘                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key Issues:**
| Issue | Description | Impact |
|-------|-------------|--------|
| **Thundering Herd** | All clusters scale up simultaneously (e.g., 9am workday start) | 90% of requests fail due to capacity exhaustion |
| **SKU Stockout** | Single popular SKU (e.g., D4s_v5) exhausted | All clusters stuck in Pending state |
| **Eviction Cascade** | Azure reclaims capacity, evicting pods across all clusters | Mass service disruption |
| **Quota Contention** | Subscription-level vCPU quotas shared across clusters | Quota exhaustion blocks scaling |

### Statistical Analysis: Failure Probability

| Clusters | Same SKU Probability | Simultaneous Scale Request | Capacity Failure Rate |
|----------|----------------------|---------------------------|----------------------|
| 1 | - | - | ~5% |
| 5 | 80% | ~3 clusters | ~25% |
| 10 | 90% | ~6 clusters | ~50% |
| 15 | 95% | ~9 clusters | ~70% |

---

## Scenario Analysis

### Scenario 1: Morning Burst (Common)

**Event:** All clusters scale up at 9:00 AM as developers start work.

**Without Mitigation:**
- 15 clusters request 10 nodes each = 150 node requests
- All request `Standard_D4s_v5` in Zone 1
- Azure capacity: ~50 nodes available
- Result: 100 nodes stuck in Pending

**With Karpenter + Diversity:**
- Karpenter selects from: `D4s_v5`, `D8s_v5`, `E4s_v5`, `E8s_v5`
- Requests spread across Zones 1, 2, 3
- Result: 95%+ success rate

### Scenario 2: Regional Eviction Event (Rare but Critical)

**Event:** Azure needs capacity for priority workloads, evicts Spot VMs region-wide.

**Without Mitigation:**
- All 15 clusters lose Spot nodes simultaneously
- Standard pools overwhelmed
- 30-minute recovery time

**With Mitigation:**
- Pod Disruption Budgets limit eviction rate
- Standard pools pre-scaled with buffer capacity
- Karpenter immediately provisions alternative SKUs
- Recovery time: 2-5 minutes

### Scenario 3: Quota Exhaustion

**Event:** Subscription vCPU quota reached.

**Symptoms:**
- Cluster Autoscaler/Karpenter log: `QuotaExceeded`
- All clusters blocked from scaling

**Mitigation:**
- Distribute clusters across multiple subscriptions
- Request quota increases proactively
- Implement quota-aware scheduling

---

## Solution Architecture

### Multi-Layer Defense

```
┌────────────────────────────────────────────────────────────────────┐
│                     LAYER 1: INSTANCE DIVERSITY                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ D4s_v5   │  │ D8s_v5   │  │ E4s_v5   │  │ F8s_v2   │          │
│  │ (25%)    │  │ (25%)    │  │ (25%)    │  │ (25%)    │          │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘          │
├────────────────────────────────────────────────────────────────────┤
│                     LAYER 2: ZONE DISTRIBUTION                      │
│      Zone 1 (33%)      Zone 2 (33%)      Zone 3 (34%)            │
├────────────────────────────────────────────────────────────────────┤
│                     LAYER 3: KARPENTER (NAP)                        │
│  • Dynamic SKU selection based on availability                      │
│  • Automatic Spot → On-Demand fallback                             │
│  • Consolidation for cost optimization                              │
├────────────────────────────────────────────────────────────────────┤
│                     LAYER 4: FLEET COORDINATION                     │
│  • Staggered scaling windows per cluster                            │
│  • Quota distribution across subscriptions                          │
│  • Cross-cluster health observability                               │
└────────────────────────────────────────────────────────────────────┘
```

---

## Karpenter Implementation

### Why Karpenter (AKS Node Autoprovisioning)?

| Feature | Native Autoscaler | Karpenter (NAP) |
|---------|-------------------|-----------------|
| SKU Selection | Fixed per pool | Dynamic from list |
| Spot Fallback | Manual pool switching | Automatic |
| Provisioning Speed | ~2-3 minutes | ~1-2 minutes |
| Bin Packing | Basic | Optimized |
| Consolidation | Manual | Automatic |

### Terraform Deployment

See [terraform/prototypes/aks-nap/main.tf](../terraform/prototypes/aks-nap/main.tf) for complete code.

```hcl
resource "azurerm_kubernetes_cluster" "nap_enabled" {
  # ...
  node_provisioning_mode = "Auto"  # Enables Karpenter
  
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
  }
}
```

### Karpenter NodePool Configuration

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: spot-flexible
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]  # Fallback enabled
        - key: kubernetes.azure.com/sku-family
          operator: In
          values: ["D", "E", "F"]  # Multiple families
        - key: kubernetes.azure.com/sku-cpu
          operator: In
          values: ["2", "4", "8", "16"]
      nodeClassRef:
        name: default
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenUnderutilized
    budgets:
      - nodes: "10%"  # Max 10% nodes disrupted at once
```

---

## Fleet Management Strategies

### Strategy 1: Staggered Scaling Windows

Prevent thundering herd by offsetting cluster scaling:

```yaml
# Cluster 1-5: Business hours scaling starts at 8:55 AM
# Cluster 6-10: Business hours scaling starts at 9:00 AM
# Cluster 11-15: Business hours scaling starts at 9:05 AM
```

### Strategy 2: Subscription Distribution

| Subscription | Clusters | vCPU Quota | Region |
|--------------|----------|------------|--------|
| Sub-Prod-A | 1-5 | 500 vCPU | West Europe |
| Sub-Prod-B | 6-10 | 500 vCPU | West Europe |
| Sub-Prod-C | 11-15 | 500 vCPU | North Europe |

### Strategy 3: SKU Affinity per Cluster Group

To avoid all clusters competing for the same SKU:

| Cluster Group | Primary SKU | Secondary SKU |
|---------------|-------------|---------------|
| 1-5 | D4s_v5 | E4s_v5 |
| 6-10 | D8s_v5 | E8s_v5 |
| 11-15 | E4s_v5 | D4s_v5 |

---

## Testing & Simulation

### Local Simulation with Kind

Since Karpenter requires Azure APIs, we simulate the **behavior** locally:

1. **Stockout Simulation**: Taint nodes as "unavailable" to force fallback
2. **Eviction Simulation**: Drain nodes to test pod rescheduling
3. **Capacity Recovery**: Uncordon nodes to simulate new capacity

See [scripts/simulate_spot_contention.sh](../scripts/simulate_spot_contention.sh) for the full script.

### Chaos Engineering Recommendations

1. **FIS (Fault Injection Simulator)**: Use Azure FIS to simulate Spot evictions
2. **Scheduled Drains**: Regularly drain Spot nodes in non-prod to test resilience
3. **Quota Throttling**: Temporarily reduce quota to test capacity-constrained behavior

---

## Decision Matrix

| Criteria | Recommendation |
|----------|----------------|
| < 5 clusters | Native Autoscaler is sufficient |
| 5-10 clusters | Consider Karpenter for flexibility |
| 10-15 clusters | **Karpenter required** + Fleet coordination |
| > 15 clusters | Multi-region + Multi-subscription mandatory |

---

## Related Documents

- [AKS Spot Node Architecture](AKS_SPOT_NODE_ARCHITECTURE.md)
- [Orchestration Plan](spot-research/orchestration-plan.md)
- [Karpenter Prototype](../terraform/prototypes/aks-nap/)

---

*End of Document*
