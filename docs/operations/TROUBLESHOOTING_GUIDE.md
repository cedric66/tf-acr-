# AKS Spot Optimization: Troubleshooting Guide

**Purpose:** Symptom-first diagnostic reference for AKS spot node issues
**Audience:** SRE, Platform Engineers, DevOps Teams
**Last Updated:** 2026-02-08

> **How to use this guide:** Find your symptom in the table below, follow the diagnostic tree, then use the linked runbook or fix for resolution. For incident response procedures, see [SRE_OPERATIONAL_RUNBOOK.md](SRE_OPERATIONAL_RUNBOOK.md).

---

## Quick Reference: Symptom Lookup

| Symptom | Likely Cause | Section |
|---------|-------------|---------|
| Pods stuck in Pending | Capacity, tolerations, PDB | [1.1](#11-pods-stuck-in-pending) |
| Pods crashing after eviction | Missing graceful shutdown | [1.2](#12-pods-crashing-or-error-after-eviction) |
| Pods on wrong node type | Missing affinity/toleration | [1.3](#13-pods-not-scheduling-on-spot-nodes) |
| Pods stuck on standard after spot returns | Sticky fallback, descheduler | [1.4](#14-pods-stuck-on-standard-nodes-sticky-fallback) |
| Node stuck NotReady | VMSS ghost instance | [2.1](#21-node-stuck-in-notready-or-unknown) |
| Nodes not scaling up | Autoscaler backoff, quota | [2.2](#22-spot-nodes-not-scaling-up) |
| Nodes not scaling down | PDB, local storage, utilization | [2.3](#23-nodes-not-scaling-down) |
| Autoscaler picking wrong pool | Priority Expander missing | [3.1](#31-autoscaler-selecting-wrong-pool) |
| Autoscaler not responding | Backoff, crash, misconfiguration | [3.2](#32-autoscaler-not-responding) |
| Cost spike / low spot adoption | Pods on standard, pool sizing | [4.1](#41-unexpected-cost-increase) |
| High eviction rate | Azure capacity, VM SKU choice | [4.2](#42-high-eviction-rate) |

---

## 1. Pod Issues

### 1.1 Pods Stuck in Pending

**Diagnostic Tree:**

```
Pods in Pending state
│
├─ kubectl describe pod <pod> → check Events section
│
├─ "no nodes available to schedule"
│  ├─ Are spot nodes present?
│  │  ├─ YES → Check tolerations (missing spot toleration?)
│  │  └─ NO → Check autoscaler (Section 3.2)
│  │
│  └─ Are standard nodes present?
│     ├─ YES but full → Autoscaler should scale up (wait 2 min)
│     └─ NO → Cluster-level issue (check kubectl get nodes)
│
├─ "Insufficient cpu/memory"
│  ├─ Nodes exist but no room → Autoscaler should provision more
│  ├─ Check: kubectl top nodes (are existing nodes full?)
│  └─ Check: Resource requests vs node capacity
│
├─ "didn't match Pod's node affinity/selector"
│  ├─ Hard affinity (required) blocking scheduling
│  └─ Fix: Change to preferredDuringScheduling (soft affinity)
│
└─ "pod topology spread constraints not satisfied"
   ├─ Check: whenUnsatisfiable should be "ScheduleAnyway"
   └─ If "DoNotSchedule" → pods blocked until spread is balanced
```

**Quick Diagnosis:**

```bash
# Why is the pod pending?
kubectl describe pod <pod-name> -n <namespace> | grep -A15 Events

# What's the autoscaler doing about it?
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50 | \
  grep -E "scale|pending|unschedulable"

# Are nodes available?
kubectl get nodes -o wide
kubectl top nodes
```

**Common Fixes:**

| Cause | Fix |
|-------|-----|
| Missing spot toleration | Add toleration to pod spec ([DevOps Guide](DEVOPS_TEAM_GUIDE.md) Method 1) |
| Topology spread with `DoNotSchedule` | Change to `whenUnsatisfiable: ScheduleAnyway` |
| All pools at max_count | Increase max_count in Terraform ([Runbook 10c](SRE_OPERATIONAL_RUNBOOK.md)) |
| VM quota exceeded | Request quota increase in Azure Portal |
| Autoscaler in backoff | Wait for backoff expiry or restart autoscaler ([Runbook 9](SRE_OPERATIONAL_RUNBOOK.md)) |

**Runbook:** [SRE Runbook 3 - Pods Stuck in Pending](SRE_OPERATIONAL_RUNBOOK.md)

---

### 1.2 Pods Crashing or Error After Eviction

**Diagnostic Tree:**

```
Pods crash/error during spot eviction
│
├─ CrashLoopBackOff after reschedule
│  ├─ Check logs: kubectl logs <pod> --previous
│  ├─ Likely: App crashed during shutdown, left corrupted state
│  └─ Fix: Implement proper SIGTERM handler
│
├─ 5xx errors during eviction window
│  ├─ Check: Does pod have preStop hook?
│  │  ├─ NO → Add preStop with sleep 25
│  │  └─ YES → Check terminationGracePeriodSeconds >= 35
│  │
│  ├─ Check: Does readiness probe mark pod NotReady quickly?
│  │  ├─ failureThreshold too high → Reduce to 2
│  │  └─ periodSeconds too long → Reduce to 5
│  │
│  └─ Check: Is app handling SIGTERM?
│     └─ App must stop accepting connections on SIGTERM
│
└─ Connection refused / timeouts
   ├─ Pod removed from Service but connections in flight
   ├─ Fix: preStop sleep allows load balancer to drain
   └─ Ensure preStop sleep (25s) > LB drain time
```

**Quick Diagnosis:**

```bash
# Check recent eviction events
kubectl get events -A --sort-by='.lastTimestamp' | grep -i evict | tail -10

# Check pod spec for graceful shutdown config
kubectl get deployment <name> -o yaml | \
  grep -E "preStop|terminationGrace|readiness" -A3

# Check application logs during eviction
kubectl logs <pod-name> --previous --tail=50
```

**Graceful Shutdown Checklist:**

- [ ] `preStop` hook with `sleep 25` (connection draining)
- [ ] `terminationGracePeriodSeconds: 35` (>= preStop + 10s buffer)
- [ ] App handles SIGTERM (stops accepting, finishes in-flight)
- [ ] Readiness probe: `failureThreshold: 2`, `periodSeconds: 5`

**Reference:** [DevOps Guide - Graceful Shutdown](DEVOPS_TEAM_GUIDE.md) for Node.js/Python/Go examples

---

### 1.3 Pods Not Scheduling on Spot Nodes

**Diagnostic Tree:**

```
Pods always land on standard nodes, never spot
│
├─ Check: Does pod have spot toleration?
│  kubectl get pod <pod> -o yaml | grep -A5 tolerations
│  ├─ NO toleration → Add it (see fix below)
│  └─ YES → Continue
│
├─ Check: Are spot nodes available?
│  kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot
│  ├─ NO spot nodes → Spot pools at 0 (capacity issue or min_count=0)
│  └─ YES → Continue
│
├─ Check: Are spot nodes full?
│  kubectl top nodes | grep spot
│  ├─ YES → Autoscaler should scale up, or reduce resource requests
│  └─ NO → Continue
│
├─ Check: Do spot nodes have correct taint?
│  kubectl describe node <spot-node> | grep -A3 Taints
│  └─ Expected: kubernetes.azure.com/scalesetpriority=spot:NoSchedule
│
└─ Check: Node affinity conflict
   kubectl get pod <pod> -o yaml | grep -A20 affinity
   └─ Hard affinity (required) for standard nodes blocks spot scheduling
```

**Quick Fix - Add Spot Toleration:**

```yaml
tolerations:
  - key: kubernetes.azure.com/scalesetpriority
    operator: Equal
    value: spot
    effect: NoSchedule
```

**Quick Fix - Add Spot Preference:**

```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
            - key: kubernetes.azure.com/scalesetpriority
              operator: In
              values: [spot]
```

**Reference:** [DevOps Guide - Deploying to Spot](DEVOPS_TEAM_GUIDE.md)

---

### 1.4 Pods Stuck on Standard Nodes (Sticky Fallback)

**Symptom:** Spot nodes are available and have capacity, but pods remain on standard nodes after a previous eviction event.

**Diagnostic Tree:**

```
Pods on standard despite spot availability
│
├─ Is Descheduler installed?
│  kubectl get pods -n kube-system -l app=descheduler
│  ├─ NO → Install descheduler (see below)
│  └─ YES → Continue
│
├─ Is Descheduler running successfully?
│  kubectl logs -n kube-system -l app=descheduler --tail=20
│  ├─ Errors → Check policy ConfigMap
│  └─ "no pods to evict" → Check pod affinity (Step 3)
│
├─ Do pods have preferredDuringScheduling affinity for spot?
│  kubectl get deployment <name> -o yaml | grep -A15 nodeAffinity
│  ├─ NO preference → Add it (descheduler needs this to detect misplacement)
│  └─ YES → Continue
│
└─ Are PDBs blocking descheduler evictions?
   kubectl get pdb -A
   ├─ ALLOWED = 0 → PDB prevents eviction (correct, wait for more replicas)
   └─ ALLOWED > 0 → Check descheduler schedule interval
```

**Quick Diagnosis:**

```bash
# Count pods per node type
kubectl get pods -n <namespace> -o json | \
  jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
  xargs -I {} kubectl get node {} \
    -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}{"\n"}' 2>/dev/null | \
  sort | uniq -c

# Check descheduler status and last run
kubectl get cronjob -n kube-system | grep descheduler
kubectl get jobs -n kube-system | grep descheduler | tail -5
```

**This is expected Kubernetes behavior.** The scheduler is a one-shot operation and does not rebalance running pods. The Descheduler solves this.

**Runbook:** [SRE Runbook 7 - Descheduler Not Rebalancing](SRE_OPERATIONAL_RUNBOOK.md)
**Deep Dive:** [Spot Eviction Scenarios - Sticky Fallback](SPOT_EVICITION_SCENARIOS.md)

---

## 2. Node Issues

### 2.1 Node Stuck in NotReady or Unknown

**Diagnostic Tree:**

```
Node in NotReady/Unknown state
│
├─ How long has node been NotReady?
│  kubectl get nodes | grep NotReady
│
├─ < 3 minutes
│  └─ Wait. Automated mitigations will handle:
│     - scale_down_unready (3m) removes ghost nodes
│     - AKS node auto-repair detects after ~5m
│
├─ 3-10 minutes
│  ├─ Check if it's a VMSS ghost instance:
│  │  NODE_RG=$(az aks show -g <rg> -n <cluster> --query nodeResourceGroup -o tsv)
│  │  az vmss list-instances -g $NODE_RG -n <vmss> \
│  │    --query "[].{name:name,state:provisioningState}" -o table
│  │
│  ├─ provisioningState = "Failed" or "Unknown"
│  │  └─ VMSS ghost. Delete instance:
│  │     az vmss delete-instances -g $NODE_RG -n <vmss> --instance-ids <id>
│  │     kubectl delete node <ghost-node>
│  │
│  └─ provisioningState = "Succeeded"
│     └─ Node exists but kubelet unhealthy. Check:
│        kubectl describe node <node> | grep -A20 Conditions
│        - MemoryPressure, DiskPressure → resource exhaustion
│        - NetworkUnavailable → CNI issue
│
└─ > 10 minutes
   ├─ max_node_provisioning_time should have handled this
   ├─ Manual intervention required (delete node + VMSS instance)
   └─ If persists after manual delete → Azure support ticket
```

**Quick Diagnosis:**

```bash
# Check node status and age
kubectl get nodes -o wide | grep -E "NotReady|Unknown"

# Check VMSS instance state
NODE_RG=$(az aks show -g <resource-group> -n <cluster-name> \
  --query nodeResourceGroup -o tsv)
az vmss list -g $NODE_RG -o table
az vmss list-instances -g $NODE_RG -n <vmss-name> \
  --query "[].{name:name, state:provisioningState, zone:zones[0]}" -o table

# Check autoscaler awareness
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50 | \
  grep -E "NotReady|unready|ghost"
```

**Runbook:** [SRE Runbook 5 - VMSS Ghost Instance](SRE_OPERATIONAL_RUNBOOK.md)
**Runbook:** [SRE Runbook 5b - Non-Ghost NotReady](SRE_OPERATIONAL_RUNBOOK.md)

---

### 2.2 Spot Nodes Not Scaling Up

**Diagnostic Tree:**

```
Pending pods but no new spot nodes appearing
│
├─ Is autoscaler running?
│  kubectl get pods -n kube-system -l app=cluster-autoscaler
│  ├─ NO pods → Autoscaler not deployed (check AKS config)
│  └─ YES → Continue
│
├─ Is autoscaler attempting scale-up?
│  kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100 | \
│    grep -E "ScaleUp|scale.up"
│  ├─ "ScaleUp: no candidates" → All pools at max or in backoff
│  ├─ "FailedScaleUp" → VMSS provisioning failed (see below)
│  └─ No scale-up entries → Check if pods match any pool's constraints
│
├─ Is a pool in backoff?
│  kubectl get cm cluster-autoscaler-status -n kube-system -o yaml | \
│    grep -A5 "Backoff"
│  └─ YES → See Runbook 9 (Autoscaler Backoff)
│
├─ Is VM quota exceeded?
│  az vm list-usage --location <region> -o table | grep -E "DSv5|ESv5|FSv2"
│  └─ CurrentValue near Limit → Request quota increase
│
└─ Is there no spot capacity in Azure?
   ├─ Check Azure spot pricing dashboard for region
   ├─ Priority Expander should fall back to standard pool (tier 20)
   └─ If standard not scaling either → See Runbook 8 (Capacity Exhaustion)
```

**Quick Diagnosis:**

```bash
# Autoscaler log summary
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=200 | \
  grep -cE "ScaleUp|FailedScaleUp|Backoff|Error"

# Current pool sizes vs limits
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot \
  -o custom-columns=NAME:.metadata.name,POOL:.metadata.labels.agentpool

# Priority Expander ConfigMap present?
kubectl get cm cluster-autoscaler-priority-expander -n kube-system
```

**Runbook:** [SRE Runbook 8 - Capacity Exhaustion](SRE_OPERATIONAL_RUNBOOK.md)
**Runbook:** [SRE Runbook 9 - Autoscaler Backoff](SRE_OPERATIONAL_RUNBOOK.md)

---

### 2.3 Nodes Not Scaling Down

**Symptom:** Underutilized nodes remain in the cluster, autoscaler not removing them.

**Diagnostic Tree:**

```
Underutilized nodes not being removed
│
├─ Check autoscaler's scale-down status
│  kubectl get cm cluster-autoscaler-status -n kube-system -o yaml | \
│    grep -A20 "ScaleDown"
│
├─ "NoCandidates"
│  ├─ Node utilization > 50% (scale_down_utilization_threshold)
│  │  └─ Expected behavior - node is not underutilized
│  ├─ Pods with local storage on node
│  │  └─ skip_nodes_with_local_storage prevents scale-down
│  └─ System pods on node
│     └─ skip_nodes_with_system_pods prevents scale-down
│
├─ "Unneeded" but not scaling down
│  ├─ Node been unneeded < 5 minutes (scale_down_unneeded)
│  │  └─ Wait - node must be unneeded for full duration
│  └─ PDB preventing pod eviction during drain
│     └─ kubectl get pdb -A (check ALLOWED column)
│
└─ Scale-down disabled
   └─ Check: cluster-autoscaler.kubernetes.io/scale-down-disabled annotation
      kubectl get nodes -o json | jq '.items[] |
        select(.metadata.annotations["cluster-autoscaler.kubernetes.io/scale-down-disabled"]=="true") |
        .metadata.name'
```

**Quick Diagnosis:**

```bash
# What pods prevent scale-down on a specific node?
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=<node-name>

# Check node utilization
kubectl top node <node-name>

# Check for scale-down-disabled annotation
kubectl describe node <node-name> | grep scale-down-disabled
```

---

## 3. Autoscaler Issues

### 3.1 Autoscaler Selecting Wrong Pool

**Symptom:** Autoscaler scales up standard pool instead of spot, or selects expensive spot pool over cheaper ones.

**Diagnostic Tree:**

```
Wrong pool selected for scale-up
│
├─ Is Priority Expander ConfigMap present?
│  kubectl get cm cluster-autoscaler-priority-expander -n kube-system
│  ├─ NOT FOUND → Autoscaler using "random" expander (no cost optimization)
│  │  └─ Deploy ConfigMap via Terraform or kubectl (see Deployment Guide §4)
│  └─ EXISTS → Continue
│
├─ Is expander set to "priority"?
│  kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50 | \
│    grep -i "expander"
│  ├─ "random" or "least-waste" → Module misconfigured
│  │  └─ Check: variable auto_scaler_profile.expander = "priority"
│  └─ "priority" → Continue
│
├─ Does ConfigMap have correct pool regex patterns?
│  kubectl get cm cluster-autoscaler-priority-expander -n kube-system -o yaml
│  ├─ Missing pool → Add regex pattern for the pool
│  └─ Wrong priority number → Adjust (lower = preferred)
│
└─ Preferred pool at max capacity or in backoff
   └─ Expected: Expander falls through to next tier
      Check autoscaler logs for "tried priority X, falling back to Y"
```

**Expected Priority Order:**

```
Priority 5:  spotmemory1, spotmemory2     (E-series, lowest eviction risk)
Priority 10: spotgeneral1, spotgeneral2, spotcompute  (D/F-series)
Priority 20: stdworkload                   (on-demand fallback)
Priority 30: system                        (never for user workloads)
```

**Important:** Without the Priority Expander ConfigMap, the autoscaler silently defaults to random pool selection. This is the #1 misconfiguration that eliminates cost savings.

**Reference:** [Deployment Guide §4 - Priority Expander Setup](DEPLOYMENT_GUIDE.md)

---

### 3.2 Autoscaler Not Responding

**Symptom:** Pending pods but autoscaler appears inactive - no scale-up or scale-down activity.

**Quick Diagnosis:**

```bash
# Is the autoscaler pod running?
kubectl get pods -n kube-system -l app=cluster-autoscaler

# Is the autoscaler healthy?
kubectl get cm cluster-autoscaler-status -n kube-system -o yaml | head -30

# Recent autoscaler activity (any at all?)
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100 --since=10m

# Autoscaler error count
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=500 | \
  grep -c -i error
```

**Common Causes:**

| Cause | Diagnosis | Fix |
|-------|-----------|-----|
| Pod not running | `kubectl get pods -n kube-system -l app=cluster-autoscaler` | Check AKS cluster config, autoscaler should be enabled |
| Crash loop | Pod restarts > 0 | Check logs: `kubectl logs -n kube-system -l app=cluster-autoscaler --previous` |
| All pools in backoff | Status ConfigMap shows "Backoff" | Wait for expiry or restart autoscaler ([Runbook 9](SRE_OPERATIONAL_RUNBOOK.md)) |
| Azure API errors | Logs show "context deadline exceeded" | Transient - will recover. If persistent, check AKS managed identity permissions |
| Stale status | `lastProbeTime` is old | Restart autoscaler: `kubectl rollout restart deployment cluster-autoscaler -n kube-system` |

**Runbook:** [SRE Runbook 9 - Autoscaler Backoff](SRE_OPERATIONAL_RUNBOOK.md)

---

## 4. Cost & Efficiency Issues

### 4.1 Unexpected Cost Increase

**Diagnostic Tree:**

```
Cost higher than expected
│
├─ Check spot vs standard distribution
│  kubectl get nodes -o custom-columns=\
│    NAME:.metadata.name,\
│    PRIORITY:.metadata.labels.kubernetes\.azure\.com/scalesetpriority
│
├─ < 50% on spot
│  ├─ Were there recent evictions?
│  │  kubectl get events -A --sort-by='.lastTimestamp' | grep -i evict
│  │  └─ YES → Sticky fallback. Check descheduler (Section 1.4)
│  │
│  ├─ Are spot pools at 0 nodes?
│  │  kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot | wc -l
│  │  └─ YES → Spot capacity issue. Check autoscaler (Section 2.2)
│  │
│  └─ Are pods missing spot tolerations?
│     └─ Many pods on standard by default → DevOps teams need migration
│
├─ Standard pool over-provisioned
│  ├─ Nodes underutilized: kubectl top nodes | grep std
│  ├─ scale_down_unneeded may be too long
│  └─ PDBs may block scale-down (Section 2.3)
│
└─ Spot pricing increased
   ├─ Check Azure spot pricing dashboard
   ├─ spot_max_price = -1 means "up to on-demand price"
   └─ If spot price approaches on-demand → savings reduced
```

**Quick Diagnosis:**

```bash
# Pod distribution: spot vs standard
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
  sort -u | \
  xargs -I {} sh -c 'echo -n "{}: "; kubectl get node {} -o jsonpath="{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}" 2>/dev/null; echo' | \
  awk -F': ' '{print $2}' | sort | uniq -c

# Node count by pool
kubectl get nodes --show-labels | \
  awk '{print $6}' | grep agentpool | sort | uniq -c
```

**Runbook:** [SRE Runbook 4 - Cost Spike](SRE_OPERATIONAL_RUNBOOK.md)

---

### 4.2 High Eviction Rate

**Symptom:** >20 evictions per hour, frequent pod rescheduling.

**Quick Diagnosis:**

```bash
# Eviction count in the last hour
kubectl get events -A --sort-by='.lastTimestamp' | \
  grep -i evict | \
  awk '{print $1}' | wc -l

# Evictions by node pool
kubectl get events -A --sort-by='.lastTimestamp' | \
  grep -i evict | \
  awk '{print $1}' | sort | uniq -c | sort -rn

# Which VM SKUs are being evicted most?
# Check Azure Spot Eviction Rate data:
# Azure Portal → Virtual Machine Scale Sets → <vmss> → Spot → Eviction Rate
```

**Common Causes & Fixes:**

| Cause | Indicator | Fix |
|-------|-----------|-----|
| Spot pricing spike | Azure spot price nearing on-demand | Wait - prices typically normalize within hours |
| Under-diversified pools | Evictions concentrated in one VM family | Add pools with different VM families (D, E, F) |
| Single-zone pools | All pools in same zone getting evicted | Spread pools across zones 1, 2, 3 |
| High-demand VM SKU | Popular SKU (e.g., D4s_v5) evicted frequently | Consider less popular SKUs or larger sizes |

**Runbook:** [SRE Runbook 1 - High Eviction Rate](SRE_OPERATIONAL_RUNBOOK.md)

---

## 5. Descheduler Issues

### 5.1 Descheduler Not Installed

**Symptom:** Pods never return to spot nodes after eviction recovery.

**Verify:**

```bash
kubectl get pods -n kube-system -l app=descheduler
kubectl get cronjob -n kube-system | grep descheduler
```

**Install:**

```bash
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler/
helm install descheduler descheduler/descheduler \
  --namespace kube-system \
  --set schedule="*/5 * * * *" \
  --set deschedulerPolicy.strategies.RemovePodsViolatingNodeAffinity.enabled=true \
  --set "deschedulerPolicy.strategies.RemovePodsViolatingNodeAffinity.params.nodeAffinityType[0]=preferredDuringSchedulingIgnoredDuringExecution"
```

**Runbook:** [SRE Runbook 7 - Descheduler Not Rebalancing](SRE_OPERATIONAL_RUNBOOK.md)

### 5.2 Descheduler Running But Not Moving Pods

**Quick Diagnosis:**

```bash
# Check last run
kubectl get jobs -n kube-system | grep descheduler | tail -3

# Check logs for eviction activity
kubectl logs -n kube-system -l app=descheduler --tail=50

# Expected: "evicted pod X from node Y" messages
# Problem: "no pods to evict" or "can't evict pod" messages
```

**Common Causes:**

| Cause | Fix |
|-------|-----|
| Pods lack `preferredDuringScheduling` affinity for spot | Add node affinity preference ([DevOps Guide](DEVOPS_TEAM_GUIDE.md)) |
| PDB ALLOWED = 0 | Scale up deployment to allow PDB room |
| Descheduler policy missing `RemovePodsViolatingNodeAffinity` | Update policy ConfigMap |
| Spot nodes full | Autoscaler needs to provision more spot nodes first |

---

## 6. Common Diagnostic Commands

### Cluster Overview

```bash
# Full cluster health snapshot
echo "=== Nodes ==="
kubectl get nodes -o wide
echo "=== Pending Pods ==="
kubectl get pods -A --field-selector=status.phase=Pending
echo "=== Recent Events ==="
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
echo "=== Autoscaler Status ==="
kubectl get cm cluster-autoscaler-status -n kube-system -o yaml | head -40
```

### Spot-Specific Diagnostics

```bash
# Spot node count and status
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o wide

# Pod distribution across node types
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
  sort -u | while read node; do
    priority=$(kubectl get node "$node" \
      -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}' 2>/dev/null)
    pods=$(kubectl get pods -A --field-selector spec.nodeName="$node" --no-headers 2>/dev/null | wc -l)
    echo "$node: $priority ($pods pods)"
  done

# Autoscaler log summary (last 10 minutes)
kubectl logs -n kube-system -l app=cluster-autoscaler --since=10m | \
  grep -cE "ScaleUp|ScaleDown|FailedScaleUp|Backoff|Error"
```

### VMSS Diagnostics

```bash
# Get node resource group
NODE_RG=$(az aks show -g <resource-group> -n <cluster-name> \
  --query nodeResourceGroup -o tsv)

# List all VMSS with capacity
az vmss list -g $NODE_RG --query "[].{name:name, capacity:sku.capacity}" -o table

# Check instance health for a specific VMSS
az vmss list-instances -g $NODE_RG -n <vmss-name> \
  --query "[].{name:name, state:provisioningState, zone:zones[0]}" -o table
```

---

## Related Documentation

| Document | When to Use |
|----------|-------------|
| [SRE Operational Runbook](SRE_OPERATIONAL_RUNBOOK.md) | Incident response procedures (Runbooks 1-10) |
| [DevOps Team Guide](DEVOPS_TEAM_GUIDE.md) | Application deployment on spot nodes |
| [Deployment Guide](DEPLOYMENT_GUIDE.md) | New cluster deployment (greenfield) |
| [Migration Guide](MIGRATION_GUIDE.md) | Converting existing clusters to spot |
| [Spot Eviction Scenarios](SPOT_EVICITION_SCENARIOS.md) | Detailed eviction behavior and sticky fallback |
| [Chaos Engineering Tests](CHAOS_ENGINEERING_TESTS.md) | Resilience validation scenarios |
| [AKS Spot Architecture](AKS_SPOT_NODE_ARCHITECTURE.md) | Core technical design decisions |

---

**Document Maintenance**

This guide should be updated:
- When new failure modes are discovered
- After P1/P2 incidents that reveal diagnostic gaps
- When autoscaler or AKS behavior changes
- When new node pools or VM SKUs are added

**Last Review:** 2026-02-08
**Next Review Due:** 2026-03-08
