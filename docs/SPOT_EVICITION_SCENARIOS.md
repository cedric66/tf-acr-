# AKS Spot Eviction Scenarios & Re-scheduling

This document details the observed behavior of workloads during Spot VM evictions and provides solutions for operational challenges including the "Sticky Fallback" problem, VMSS ghost instances, and cross-zone replacement behavior.

## Observed Scenarios

| Scenario | Event | Observed Behavior | Status |
| :--- | :--- | :--- | :--- |
| **1. Failover** | Spot Pool 1 evicted | Pods automatically reschedule to Spot Pool 2. | Correct |
| **2. Fallback** | All Spot Pools evicted | Pods automatically reschedule to the Standard (On-Demand) pool. | Correct |
| **3. Recovery** | Spot capacity returns | **Pods stay on the Standard pool** despite Spot availability. | Sub-optimal |
| **4. VMSS Ghost** | Spot node evicted, VMSS instance stuck | Node stuck in NotReady/Unknown, **no replacement provisioned** in pool. | Requires mitigation |

---

## The "Sticky Fallback" Problem

By default, the Kubernetes Scheduler is a "one-shot" operation. Once a pod is successfully scheduled on a node (the Standard node in Scenario 2), it will stay there until it is deleted, the node is drained, or the pod restarts. It **will not** automatically relocate just because a "better" (cheaper) node becomes available.

### Why this happens:
1. **No Preemption**: Standard nodes have equal or higher priority than Spot nodes in the eyes of the scheduler once running.
2. **Cost-Unawareness**: The default scheduler doesn't continuously evaluate "cost-efficiency" for already running pods.
3. **Cluster Autoscaler Limitation**: The Autoscaler only scales *down* Standard nodes if they are underutilized, but it won't move pods to Spot nodes to *create* that underutilization.

---

## Solution: Kubernetes Descheduler

To solve this, we implement the **Kubernetes Descheduler** with the `RemovePodsViolatingNodeAffinity` strategy.

### 1. Configuration Principle
We configure our pods to **prefer** Spot nodes using `preferredDuringSchedulingIgnoredDuringExecution`.

```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: kubernetes.azure.com/scalesetpriority
          operator: In
          values:
          - spot
```

### 2. Descheduler Strategy
The Descheduler runs as a CronJob or Deployment and looks for pods that are on nodes that no longer match their "preferred" affinity (i.e., they are on Standard nodes while Spot nodes have room).

**Descheduler Policy Example:**
```yaml
apiVersion: descheduler/v1alpha1
kind: DeschedulerPolicy
strategies:
  "RemovePodsViolatingNodeAffinity":
    enabled: true
    params:
      nodeAffinityType:
        - "preferredDuringSchedulingIgnoredDuringExecution"
```

### 3. How it Works during Recovery (Scenario 3)
1. **Spot Pool Returns**: Cluster Autoscaler sees Spot nodes are available.
2. **Descheduler Runs**: It identifies pods on `Standard` nodes that have a `preferred` affinity for `Spot` nodes.
3. **Eviction**: Descheduler evicts those pods from the Standard nodes.
4. **Rescheduling**: The Scheduler picks up the evicted pods and, seeing available Spot nodes, places them back on the cheaper capacity.

---

## VMSS Ghost Instance Problem (Scenario 4)

After spot eviction with `Delete` policy, the VMSS instance sometimes gets stuck in `Unknown` or `Failed` provisioning state instead of being removed from the scale set. This is an Azure platform behavior that creates a cascade of problems.

### What happens:

```
T+0s:    Azure evicts spot VM
T+0s:    Eviction policy "Delete" should remove VMSS instance
T+0s:    VMSS instance gets STUCK in Unknown/Failed state
T+0s:    Kubernetes node shows "NotReady"
T+20s:   Autoscaler scans -> sees pool has current_count == desired (ghost counted)
T+20s:   Autoscaler does NOT scale up this pool
T+20s:   Pending pods -> Priority Expander tries OTHER pools (cross-pool fallback)
T+3m:    scale_down_unready removes ghost node from Kubernetes API
T+5m:    AKS node auto-repair detects NotReady -> reimages or replaces
T+10m:   max_node_provisioning_time expires -> autoscaler marks as failed
```

### Why no replacement appears in a different zone:

Each node pool is backed by **one VMSS** pinned to its configured zones (e.g., `spotmemory1` with `zones = ["2"]`). The Cluster Autoscaler can only provision within that pool's VMSS zones. It cannot create a node in Zone 1 for a pool that is configured for Zone 2.

**Cross-zone replacement only happens at the pool level**, via the Priority Expander selecting a different pool that happens to be in a different zone. For example:

| Pool | Zone | Priority | What happens if stuck |
|------|------|----------|----------------------|
| `spotmemory1` | 2 | 5 | Ghost blocks this pool |
| `spotmemory2` | 3 | 5 | Priority Expander tries this next |
| `spotgeneral1` | 1 | 10 | Then this |
| `stdworkload` | 1-2 | 20 | Final fallback (on-demand) |

### Automated mitigations:

| Mechanism | Setting | What It Does |
|-----------|---------|-------------|
| AKS Node Auto-Repair | Always on | Detects NotReady nodes after ~5 minutes, reimages or replaces |
| `scale_down_unready` | `3m` | Autoscaler removes ghost NotReady nodes after 3 minutes |
| `max_node_provisioning_time` | `10m` | Autoscaler abandons stuck provisioning and retries |
| `max_unready_nodes` | `3` | Autoscaler continues scaling even with up to 3 unready nodes |
| Priority Expander | Tiered fallback | Pending pods route to other spot pools or standard pool |

### Manual remediation:

```bash
# 1. Find the stuck VMSS instance
NODE_RG=$(az aks show -g <rg> -n <cluster> --query nodeResourceGroup -o tsv)
az vmss list-instances -g $NODE_RG -n <vmss-name> \
  --query "[].{name:name, state:provisioningState, zone:zones[0]}" -o table

# 2. Delete the ghost instance
az vmss delete-instances -g $NODE_RG -n <vmss-name> --instance-ids <instance-id>

# 3. Remove ghost node from Kubernetes
kubectl delete node <ghost-node-name>
```

See [SRE_OPERATIONAL_RUNBOOK.md](SRE_OPERATIONAL_RUNBOOK.md) Runbook 5 for the complete procedure.

---

## Recommended Implementation

For production clusters, we recommend:
1. **Low Frequency**: Run the Descheduler every 5-10 minutes to avoid constant pod churn.
2. **Pod Disruption Budgets (PDBs)**: Always ensure PDBs are in place so the Descheduler doesn't evict too many replicas at once.
3. **Exclusion Labels**: Use labels to prevent the Descheduler from touching critical or sensitive pods that shouldn't be moved.

---

## How to Test These Scenarios

We have provided dedicated test manifests in the `tests/manifests/` directory to help you validate these behaviors:

### 1. Deploy the Test Workload
Deploy a 6-replica application that prefers Spot nodes:
```bash
kubectl apply -f tests/manifests/eviction-test-workload.yaml
```

### 2. Simulate Eviction
Trigger an eviction or scale down the Spot pools. Observe the pods moving to Standard nodes (Scenario 2).

### 3. Recover Spot Capacity
Scale the Spot pools back up. Observe that the pods **do not** automatically move back (Scenario 3 - Sticky Fallback).

### 4. Apply the Descheduler
Apply the Descheduler policy to force the pods back to the preferred Spot nodes:
```bash
kubectl apply -f tests/manifests/descheduler-policy.yaml
```
*Note: This requires the Kubernetes Descheduler to be installed in your cluster.*

### 5. Simulate VMSS Ghost (Kind Cluster)
```bash
# Run the spot contention simulation
./scripts/simulate_spot_contention.sh all

# The simulation cordons and drains spot nodes to mimic eviction.
# In a real cluster, check for ghost nodes with:
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot | grep NotReady
```

---
**Last Updated**: 2026-02-05
**Status**: Documentation & Test Manifests Ready
