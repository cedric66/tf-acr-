# 🧪 AKS Spot Eviction Scenarios & Re-scheduling

This document details the observed behavior of workloads during Spot VM evictions and provides a solution for the "Sticky Fallback" problem where pods stay on Standard nodes even after Spot capacity returns.

## 📋 Observed Scenarios

| Scenario | Event | Observed Behavior | Status |
| :--- | :--- | :--- | :--- |
| **1. Failover** | Spot Pool 1 evicted | Pods automatically reschedule to Spot Pool 2. | ✅ Correct |
| **2. Fallback** | All Spot Pools evicted | Pods automatically reschedule to the Standard (On-Demand) pool. | ✅ Correct |
| **3. Recovery** | Spot capacity returns | **Pods stay on the Standard pool** despite Spot availability. | ⚠️ Sub-optimal |

---

## ⚡ The "Sticky Fallback" Problem
By default, the Kubernetes Scheduler is a "one-shot" operation. Once a pod is successfully scheduled on a node (the Standard node in Scenario 2), it will stay there until it is deleted, the node is drained, or the pod restarts. It **will not** automatically relocate just because a "better" (cheaper) node becomes available.

### Why this happens:
1. **No Preemption**: Standard nodes have equal or higher priority than Spot nodes in the eyes of the scheduler once running.
2. **Cost-Unawareness**: The default scheduler doesn't continuously evaluate "cost-efficiency" for already running pods.
3. **Cluster Autoscaler Limitation**: The Autoscaler only scales *down* Standard nodes if they are underutilized, but it won't move pods to Spot nodes to *create* that underutilization.

---

## 🛠️ Solution: Kubernetes Descheduler

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

### 3. How it Works during Recovery (Scenario 4)
1. **Spot Pool Returns**: Cluster Autoscaler sees Spot nodes are available.
2. **Descheduler Runs**: It identifies pods on `Standard` nodes that have a `preferred` affinity for `Spot` nodes.
3. **Eviction**: Descheduler evicts those pods from the Standard nodes.
4. **Rescheduling**: The Scheduler picks up the evicted pods and, seeing available Spot nodes, places them back on the cheaper capacity.

---

## 🚀 Recommended Implementation
For production clusters, we recommend:
1. **Low Frequency**: Run the Descheduler every 5-10 minutes to avoid constant pod churn.
2. **Pod Disruption Budgets (PDBs)**: Always ensure PDBs are in place so the Descheduler doesn't evict too many replicas at once.
3. **Exclusion Labels**: Use labels to prevent the Descheduler from touching critical or sensitive pods that shouldn't be moved.

---

## 🧪 How to Test These Scenarios

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

---
**Last Updated**: 2026-01-27  
**Status**: ✅ Documentation & Test Manifests Ready
