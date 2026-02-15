# AKS Spot Node Cost Optimization Architecture

> **Document Version:** 1.0  
> **Created:** 2026-01-12  
> **Branch:** `feature/aks-spot-node-cost-optimization`

---

## Executive Summary

This document outlines an architectural approach to reduce AKS cluster costs by **40-80%** through strategic use of Azure Spot VM instances while maintaining workload availability and resilience. The solution implements a multi-zone, multi-pool topology with intelligent pod scheduling that gracefully handles spot evictions.

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Proposed Architecture](#proposed-architecture)
3. [Node Pool Strategy](#node-pool-strategy)
4. [Pod Topology & Scheduling](#pod-topology--scheduling)
5. [Implementation Plan](#implementation-plan)
6. [Failure Cases & Mitigations](#failure-cases--mitigations)
7. [Cost Analysis](#cost-analysis)
8. [Terraform Implementation](#terraform-implementation)

---

## Current State Analysis

### Typical AKS Cost Distribution

| Component | % of Total Cost |
|-----------|-----------------|
| Compute (VMs) | 60-75% |
| Storage | 10-15% |
| Networking | 5-10% |
| Other Services | 5-10% |

**Key Insight:** Compute costs dominate AKS spending. Spot VMs offer **up to 90% discount** compared to on-demand pricing.

---

## Proposed Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AKS Cluster                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │   System Pool   │  │  Standard Pool  │  │  Standard Pool  │             │
│  │  (Always-On)    │  │   (Zone 1)      │  │   (Zone 2)      │             │
│  │                 │  │                 │  │                 │             │
│  │ • System pods   │  │ • Critical      │  │ • Critical      │             │
│  │ • CoreDNS       │  │   workloads     │  │   workloads     │             │
│  │ • kube-proxy    │  │ • Overflow      │  │ • Overflow      │             │
│  │ • CNI           │  │   from spot     │  │   from spot     │             │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘             │
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │  Spot Pool 1    │  │  Spot Pool 2    │  │  Spot Pool 3    │             │
│  │  (Zone 1)       │  │  (Zone 2)       │  │  (Zone 3)       │             │
│  │  VM Size: A     │  │  VM Size: B     │  │  VM Size: C     │             │
│  │                 │  │                 │  │                 │             │
│  │ • Stateless     │  │ • Stateless     │  │ • Stateless     │             │
│  │   workloads     │  │   workloads     │  │   workloads     │             │
│  │ • Batch jobs    │  │ • Batch jobs    │  │ • Batch jobs    │             │
│  │ • Dev/Test      │  │ • Dev/Test      │  │ • Dev/Test      │             │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Core Principles

1. **Defense in Depth**: Multiple spot pools with different VM sizes reduce simultaneous eviction risk
2. **Graceful Degradation**: Standard pools absorb overflow when spot capacity is unavailable
3. **Topology Awareness**: Pod scheduling spans across node types for continuous availability
4. **Cost-First, Availability-Second**: Prefer spot nodes but never sacrifice availability

---

## Node Pool Strategy

### Pool Configuration Matrix

| Pool Name | Type | Priority | VM Size | Zones | Min Nodes | Max Nodes | Purpose |
|-----------|------|----------|---------|-------|-----------|-----------|---------|
| `system` | Standard | High | Standard_D4s_v5 | 1,2,3 | 3 | 6 | System components |
| `standard-workload` | Standard | Medium | Standard_D4s_v5 | 1,2 | 2 | 10 | Critical workloads, overflow |
| `spot-general-a` | Spot | Low | Standard_D4s_v5 | 1 | 0 | 20 | General workloads |
| `spot-general-b` | Spot | Low | Standard_D8s_v5 | 2 | 0 | 15 | General workloads |
| `spot-compute-c` | Spot | Low | Standard_F8s_v2 | 3 | 0 | 10 | Compute-intensive |

### Why Multiple Spot Pools with Different VM Sizes?

**Azure Spot Eviction Behavior:**
- Evictions are triggered by capacity demands for **specific VM sizes** in **specific regions/zones**
- Different VM sizes have independent eviction rates
- Diversifying VM sizes significantly reduces the probability of simultaneous eviction

**Statistical Advantage:**
```
Single VM Size Eviction Risk:    ~15-20% per hour during peak
Two Different VM Sizes:          ~2-4% simultaneous eviction
Three Different VM Sizes:        ~0.3-0.8% simultaneous eviction
```

### Node Pool Labels and Taints

```yaml
# System Pool (no scheduling of user workloads)
labels:
  kubernetes.azure.com/mode: system
  node-pool-type: system
taints:
  - key: CriticalAddonsOnly
    value: "true"
    effect: NoSchedule

# Standard Workload Pool
labels:
  workload-type: standard
  node-pool-type: user
  priority: on-demand
taints: none  # Accepts both standard and spot-tolerant workloads

# Spot Pools
labels:
  workload-type: spot
  node-pool-type: user
  priority: spot
  kubernetes.azure.com/scalesetpriority: spot
taints:
  - key: kubernetes.azure.com/scalesetpriority
    value: spot
    effect: NoSchedule
```

---

## Pod Topology & Scheduling

### Topology Spread Constraints Strategy

The key to maintaining availability during spot evictions is using **topology spread constraints** combined with **node affinity** and **pod anti-affinity**.

### Deployment Template for Spot+Standard Distribution

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-workload
  labels:
    app: example
    cost-optimization: spot-preferred
spec:
  replicas: 6
  selector:
    matchLabels:
      app: example
  template:
    metadata:
      labels:
        app: example
    spec:
      # TOLERATION: Allow scheduling on spot nodes
      tolerations:
        - key: kubernetes.azure.com/scalesetpriority
          operator: Equal
          value: spot
          effect: NoSchedule
      
      # AFFINITY: Prefer spot nodes, but allow standard as fallback
      affinity:
        nodeAffinity:
          # PREFER spot nodes (soft constraint)
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.azure.com/scalesetpriority
                    operator: In
                    values:
                      - spot
            - weight: 50
              preference:
                matchExpressions:
                  - key: priority
                    operator: In
                    values:
                      - on-demand
        
        # ANTI-AFFINITY: Spread pods across nodes
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - example
                topologyKey: kubernetes.io/hostname
      
      # TOPOLOGY SPREAD: Distribute across zones and node types
      topologySpreadConstraints:
        # Spread across availability zones
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: example
        
        # Spread across node pool types (spot vs standard)
        - maxSkew: 2
          topologyKey: kubernetes.azure.com/scalesetpriority
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: example
        
        # Spread across individual nodes
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: example
      
      containers:
        - name: example
          image: example:latest
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
          
          # Graceful shutdown for spot eviction
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 25"]
          
          terminationGracePeriodSeconds: 30
```

### Topology Spread Mathematics

For a workload with **6 replicas** across the pools:

**Ideal Distribution (all pools healthy):**
```
┌─────────────────┬─────────────────┬─────────────────┐
│  Spot Pool A    │  Spot Pool B    │  Standard Pool  │
│                 │                 │                 │
│    2 pods       │    2 pods       │    2 pods       │
└─────────────────┴─────────────────┴─────────────────┘
```

**During Spot Pool A Eviction:**
```
┌─────────────────┬─────────────────┬─────────────────┐
│  Spot Pool A    │  Spot Pool B    │  Standard Pool  │
│   (evicted)     │                 │                 │
│    0 pods       │    3 pods       │    3 pods       │
└─────────────────┴─────────────────┴─────────────────┘
```

**During Both Spot Pools Eviction (rare):**
```
┌─────────────────┬─────────────────┬─────────────────┐
│  Spot Pool A    │  Spot Pool B    │  Standard Pool  │
│   (evicted)     │   (evicted)     │   (scales up)   │
│    0 pods       │    0 pods       │    6 pods       │
└─────────────────┴─────────────────┴─────────────────┘
```

---

## Implementation Plan

### Phase 1: Foundation (Week 1)

| Task | Description | Owner |
|------|-------------|-------|
| 1.1 | Create Terraform modules for spot node pools | Platform Team |
| 1.2 | Configure cluster autoscaler settings | Platform Team |
| 1.3 | Set up monitoring and alerting for evictions | SRE Team |
| 1.4 | Create Pod Disruption Budgets | App Teams |

### Phase 2: Pilot (Week 2-3)

| Task | Description | Owner |
|------|-------------|-------|
| 2.1 | Deploy spot pools with min_count=0 | Platform Team |
| 2.2 | Migrate dev/test workloads to spot | App Teams |
| 2.3 | Monitor eviction patterns and costs | SRE Team |
| 2.4 | Tune topology spread constraints | Platform Team |

### Phase 3: Production Rollout (Week 4-6)

| Task | Description | Owner |
|------|-------------|-------|
| 3.1 | Update production deployments with topology | App Teams |
| 3.2 | Enable spot pools for production workloads | Platform Team |
| 3.3 | Implement chaos engineering tests | SRE Team |
| 3.4 | Document runbooks and procedures | All Teams |

### Phase 4: Optimization (Ongoing)

| Task | Description | Owner |
|------|-------------|-------|
| 4.1 | Analyze eviction patterns | SRE Team |
| 4.2 | Optimize VM size selection | Platform Team |
| 4.3 | Implement predictive scaling | Platform Team |
| 4.4 | Regular cost reviews | FinOps Team |

---

## Failure Cases & Mitigations

### Failure Case 1: Simultaneous Multi-Pool Eviction

**Scenario:** Azure needs capacity across multiple VM sizes simultaneously, evicting all spot pools.

**Probability:** ~0.5-2% during major Azure events

**Impact:** All spot pods need immediate rescheduling to standard pools.

**Mitigations:**
1. **Standard pool auto-scaling** configured with aggressive scale-up
2. **Pod Disruption Budgets** ensure minimum replicas during transitions
3. **Cluster autoscaler priority expander** prioritizes standard pools
4. **Overprovisioning buffer** on standard pools

```yaml
# PodDisruptionBudget
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: example-pdb
spec:
  minAvailable: 50%
  selector:
    matchLabels:
      app: example
```

---

### Failure Case 2: Autoscaler Delay on Standard Pool

**Scenario:** Standard pool cannot scale fast enough to absorb evicted spot pods.

**Probability:** ~10-15% during rapid evictions

**Impact:** Pods remain Pending, causing service degradation.

**Mitigations:**
1. **Overprovisioned placeholder pods** on standard pools (using low-priority pods)
2. **Node warm pools** with pre-provisioned but cordoned nodes
3. **Aggressive autoscaler settings**:

```hcl
# Terraform - Cluster Autoscaler Profile
auto_scaler_profile {
  balance_similar_node_groups      = true
  expander                         = "priority"
  max_graceful_termination_sec     = 30
  max_node_provisioning_time       = "15m"
  max_unready_nodes                = 3
  max_unready_percentage           = 45
  new_pod_scale_up_delay           = "0s"
  scale_down_delay_after_add       = "10m"
  scale_down_delay_after_delete    = "10s"
  scale_down_delay_after_failure   = "3m"
  scale_down_unneeded              = "10m"
  scale_down_unready               = "20m"
  scale_down_utilization_threshold = 0.5
  scan_interval                    = "10s"
  skip_nodes_with_local_storage    = false
  skip_nodes_with_system_pods      = true
}
```

---

### Failure Case 3: Spot VM Unavailability at Creation

**Scenario:** No spot capacity available when cluster autoscaler tries to add spot nodes.

**Probability:** ~5-10% during peak hours

**Impact:** Spot pools remain at min_count, workloads remain on expensive standard pools.

**Mitigations:**
1. Configure **multiple VM sizes per pool** (using VM Scale Set Flex)
2. Use **spot with eviction type: Delete + max price = -1** (pay market rate)
3. Implement **fallback to standard** automatically:

```yaml
# Priority Expander ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-priority-expander
  namespace: kube-system
data:
  priorities: |-
    10:
      - spot-general-a
      - spot-general-b
      - spot-compute-c
    20:
      - standard-workload
```

---

### Failure Case 4: Topology Spread Impossible

**Scenario:** `maxSkew` cannot be satisfied across zones/node types.

**Probability:** ~2-5% during capacity constraints

**Impact:** Pods remain Pending if `whenUnsatisfiable: DoNotSchedule`.

**Mitigations:**
1. Always use `whenUnsatisfiable: ScheduleAnyway` for production
2. Monitor uneven distribution with metrics
3. Set reasonable `maxSkew` values (1-3)

---

### Failure Case 5: Stateful Workload Data Loss

**Scenario:** Stateful pod on spot node evicted before data sync.

**Probability:** ~20% per eviction event for stateful apps

**Impact:** Data loss, corruption, or inconsistency.

**Mitigations:**
1. **NEVER schedule stateful workloads on spot nodes**:

```yaml
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

2. Use **node taints** to repel stateful workloads from spot pools
3. Implement proper **volume snapshotting** regardless

---

### Failure Case 6: Cost Exceeds Budget (Spot Price Spike)

**Scenario:** Spot prices increase to near on-demand levels.

**Probability:** ~3-5% during high-demand periods

**Impact:** Minimal cost savings despite complexity.

**Mitigations:**
1. Set **max_price** to acceptable threshold (e.g., 50% of on-demand)
2. Monitor **cost per pod** metrics
3. Configure alerts for **price threshold breaches**

---

### Failure Case 7: 30-Second Eviction Window Insufficient

**Scenario:** Application requires more than 30 seconds for graceful shutdown.

**Probability:** 100% for long-shutdown apps

**Impact:** Incomplete request processing, data corruption.

**Mitigations:**
1. Implement **pre-stop hooks** for graceful shutdown
2. Configure **terminationGracePeriodSeconds** appropriately
3. Rely on **Native AKS Spot Node Auto-Drain** (enabled by default) which detects Scheduled Events and gracefully drains the node.

---

## Cost Analysis

### Projected Savings Model

| Configuration | Monthly Cost | Savings vs Baseline |
|---------------|--------------|---------------------|
| Baseline (all Standard) | $10,000 | - |
| 50% Spot Adoption | $6,500 | 35% |
| 70% Spot Adoption | $5,000 | 50% |
| 80% Spot Adoption (optimal) | $4,200 | 58% |

### Cost vs Complexity Trade-off

```
         ▲ Savings (%)
    80%  │                    ┌───────────
         │                   /│ Diminishing
    60%  │              ────/ │ Returns
         │            /       │
    40%  │         /          │
         │      /             │
    20%  │   /                │
         │ /                  │
     0%  └────────────────────┴────────────▶
         1     2     3     4     5+
                Spot Pools
```

**Sweet Spot:** 2-3 spot pools provide optimal savings-to-complexity ratio.

---

## Terraform Implementation

### Module Structure

```
terraform/
├── modules/
│   └── aks-spot-optimized/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── node-pools.tf
│       └── autoscaler.tf
├── environments/
│   ├── dev/
│   │   └── main.tf
│   ├── staging/
│   │   └── main.tf
│   └── prod/
│       └── main.tf
└── kubernetes/
    ├── priority-expander.yaml
    ├── pod-templates/
    │   ├── spot-tolerant-deployment.yaml
    │   └── standard-only-deployment.yaml
    └── pdb-templates/
        └── standard-pdb.yaml
```

### Core Terraform Configuration

See [terraform/modules/aks-spot-optimized/](../terraform/modules/aks-spot-optimized/) for complete implementation.

---

## Monitoring & Observability

### Key Metrics to Monitor

| Metric | Alert Threshold | Action |
|--------|-----------------|--------|
| Spot eviction rate | >5/hour | Review capacity |
| Pending pods duration | >2 min | Scale standard pools |
| Standard pool utilization | >80% | Add capacity |
| Cost per workload | >20% baseline | Review sizing |
| Topology imbalance | maxSkew >3 | Rebalance pods |

### Recommended Dashboards

1. **Spot Health Dashboard**: Evictions, capacity, price trends
2. **Pod Distribution Dashboard**: Topology spread visualization
3. **Cost Optimization Dashboard**: Savings vs baseline, trends

---

## Decision Matrix: What to Run Where

| Workload Type | Recommended Pool | Reason |
|---------------|------------------|--------|
| Stateful apps | Standard only | Data safety |
| Stateless APIs | Spot preferred | Cost savings |
| Batch jobs | Spot only | Interruptible |
| CI/CD runners | Spot preferred | Ephemeral |
| Databases | Standard only | Data consistency |
| Caches (Redis) | Standard preferred | Recovery time |
| Queue workers | Spot preferred | Resumable |
| Web frontends | Spot + Standard | Availability |

---

## Appendix A: Quick Reference Commands

```bash
# Check spot node status
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot

# View pod distribution across zones
kubectl get pods -o wide | grep -E "ZONE|zone"

# Check pending pods
kubectl get pods --field-selector=status.phase=Pending

# Simulate eviction (testing)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# View autoscaler status
kubectl -n kube-system logs -l app=cluster-autoscaler --tail=100
```

---

## Appendix B: Related Documents

- [Kubernetes Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)
- [Azure Spot VMs Best Practices](https://docs.microsoft.com/en-us/azure/aks/spot-node-pool)
- [Cluster Autoscaler FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)

---

## Document Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Platform Architect | | | |
| SRE Lead | | | |
| FinOps Lead | | | |
| Security Reviewer | | | |

---

*End of Document*
