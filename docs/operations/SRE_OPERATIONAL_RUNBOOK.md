# SRE Operational Runbook: AKS Spot Node Management

**Document Owner:** SRE Team  
**Created:** 2026-01-12  
**Last Updated:** 2026-01-12  
**On-Call Reference:** Priority 2

---

## Quick Reference

### Emergency Contacts
- **Platform Team:** #platform-engineering (Slack), +61-XXX-XXX-XXX
- **Escalation:** Platform Lead (on-call rotation)
- **Incident Channel:** #incident-spot-nodes

### Common Commands

```bash
# Check spot node status
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot

# View pending pods
kubectl get pods -A --field-selector=status.phase=Pending

# Manual failover to standard
kubectl cordon -l kubernetes.azure.com/scalesetpriority=spot

# View eviction events (last hour)
kubectl get events -A --sort-by='.lastTimestamp' | grep Evicted | tail -20

# Check autoscaler status
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50
```

---

## Overview

### What is Spot Node Optimization?

Spot nodes are Azure VMs offered at **60-90% discount** with the trade-off that Azure can evict them with **30 seconds notice** when capacity is needed.

**Our Architecture:**
- **3 Spot Pools** (different VM sizes, different zones) - cost-optimized
- **1 Standard Pool** - fallback for evictions
- **1 System Pool** - cluster services (never spot)

**Target State:** 75% of workloads on spot, 25% on standard

---

## Monitoring & Alerting

### Key Dashboards

| Dashboard | URL | Purpose |
|-----------|-----|---------|
| Spot Optimization Overview | Grafana → AKS → Spot Overview | Health, costs, evictions |
| Pod Distribution | Grafana → AKS → Topology | Spread across pools |
| Autoscaler Status | Grafana → AKS → Autoscaler | Scale activity |
| Cost Trends | Azure Cost Management | Spend tracking |

### Critical Alerts

| Alert | Severity | Response Time | Action |
|-------|----------|---------------|--------|
| **High Eviction Rate** (>20/hour) | P2 | 15 min | Investigate capacity issues |
| **All Spot Pools Evicted** | P1 | 5 min | Verify standard pool scaling |
| **Pods Pending >5 min** | P2 | 15 min | Check autoscaler logs |
| **PDB Violations** | P1 | 5 min | Emergency scale-up |
| **Cost Spike** (>$200/day) | P3 | 1 hour | Review spot pricing |

---

## Runbooks

### Runbook 1: High Eviction Rate Alert

**Alert:** `Spot eviction rate > 20 per hour`

**Cause:** Azure capacity demand spike in region

**Impact:** Increased pod rescheduling, potential latency spikes

**Response Procedure:**

```bash
# Step 1: Assess current eviction rate
kubectl get events -A --sort-by='.lastTimestamp' | \
  grep -i evicted | \
  awk '{print $1}' | \
  uniq -c | \
  sort -rn

# Step 2: Check pod health
kubectl get pods -A | grep -E "Pending|ContainerCreating|ImagePullBackOff"

# Step 3: Verify standard pool capacity
kubectl get nodes -l priority=on-demand -o wide

# Step 4: Check autoscaler decisions
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100 | \
  grep -E "scale|evict|spot"

# Step 5: If standard pool not scaling, manually trigger
kubectl scale deployment <deployment-name> --replicas=<current+2>

# Step 6: Document in incident channel
# Post to #incident-spot-nodes with:
# - Current eviction rate
# - Affected namespaces
# - Standard pool status
# - Mitigation actions taken
```

**Expected Resolution Time:** 5-10 minutes

**Escalation:** If pods remain Pending >10 minutes, escalate to Platform Lead

---

### Runbook 2: All Spot Pools Evicted Simultaneously

**Alert:** `All spot node pools have zero ready nodes`

**Cause:** Major Azure capacity event (rare, ~1-2% probability)

**Impact:** High - all spot workloads rescheduling to standard pool

**Response Procedure:**

```bash
# Step 1: IMMEDIATE - Verify this is real eviction, not cluster issue
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot

# Expected output: No nodes or all NotReady
# If nodes exist but NotReady, this is different issue - see Runbook 5

# Step 2: Check standard pool status
kubectl get nodes -l priority=on-demand

# Expected: Standard pool scaling up (NEW nodes in NotReady state)

# Step 3: Monitor pod rescheduling
watch "kubectl get pods -A -o wide | grep -v Running | wc -l"

# Expected: Decreasing count as pods schedule

# Step 4: Check PDB status - ensure we maintain minimums
kubectl get pdb -A

# Expected: All PDBs have ALLOWED > 0

# Step 5: Verify application health
# Check your monitoring (e.g., Datadog, New Relic)
# Expected: Request success rate >95%, latency <2x baseline

# Step 6: Create incident ticket
# Priority: P1
# Title: "All AKS spot pools evicted - failover to standard"
# Include:
# - Time of eviction
# - Number of pods affected
# - Standard pool scale-up time
# - Application impact metrics
```

**Expected Behavior:**
- T+0s: Spot pools evicted
- T+30s: All pods marked Pending
- T+60s: Standard pool autoscaler triggers
- T+180s: New standard nodes ready
- T+240s: All pods Running on standard

**Escalation:** If standard pool fails to scale within 5 minutes, escalate to Platform Lead

**Long-term Action:** Review spot pricing trends, consider adjusting VM sizes

---

### Runbook 3: Pods Stuck in Pending State

**Alert:** `Pending pods > 10 for > 5 minutes`

**Cause:** Multi-factor (capacity, scheduling constraints, resources)

**Impact:** Application degradation, reduced capacity

**Response Procedure:**

```bash
# Step 1: Identify why pods are pending
kubectl describe pod <pending-pod-name> | grep -A10 Events

# Common reasons and fixes:

## Reason 1: "Insufficient CPU/memory"
# Action: Verify autoscaler is attempting to scale
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50

## Reason 2: "No nodes available matching nodeSelector"
# Action: Check if spot pools are cordoned
kubectl get nodes | grep spot
# If cordoned, uncordon:
kubectl uncordon <node-name>

## Reason 3: "Pod topology spread constraints not satisfied"
# Action: This is expected during evictions, pods will schedule with skew
# Verify maxSkew allows "ScheduleAnyway":
kubectl get deployment <deployment> -o yaml | grep -A5 topologySpreadConstraints

## Reason 4: "spot pool has no capacity, standard pool scaling slowly"
# Action: Check Azure portal for VM provisioning status
# OR manually add standard capacity:
az aks nodepool scale \
  --resource-group rg-aks-prod \
  --cluster-name aks-prod \
  --name stdworkload \
  --node-count <current+3>
```

**Decision Tree:**
```
Pending Pods Detected
├─ Check Events
│  ├─ "Insufficient resources" → Verify autoscaler logs
│  ├─ "No nodes match" → Check node labels/taints
│  └─ "Topology spread" → Verify whenUnsatisfiable: ScheduleAnyway
├─ Duration < 2 min → Monitor (normal during eviction)
├─ Duration 2-5 min → Check autoscaler activity
└─ Duration > 5 min → Manual intervention required
```

---

### Runbook 4: Cost Spike Alert

**Alert:** `Daily AKS spend > $200 (threshold)`

**Cause:** Spot pools offline, workloads on expensive standard nodes

**Impact:** Financial - reduced savings

**Response Procedure:**

```bash
# Step 1: Check current node distribution
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
PRIORITY:.metadata.labels.kubernetes\\.azure\\.com/scalesetpriority,\
SIZE:.metadata.labels.beta\\.kubernetes\\.io/instance-type

# Step 2: Count pods per node type
kubectl get pods -A -o json | \
jq -r '.items[] | .spec.nodeName' | \
xargs -I {} kubectl get node {} -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}{"\n"}' | \
sort | uniq -c

# Expected: 70-80% on spot
# If <50% on spot, investigate

# Step 3: Check spot pricing
# Go to Azure Portal → Virtual Machines → Spot Pricing
# Review current spot prices vs on-demand

# Step 4: Decision matrix
if [ spot_price > 0.5 * ondemand_price ]; then
  echo "Spot pricing acceptable, should use spot"
  # Investigate why workloads not on spot
  kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot
fi

# Step 5: If spot pools available but unused
# Check if pods have proper tolerations
kubectl get deployment <deployment> -o yaml | grep -A5 tolerations

# Step 6: Document in #finops-alerts channel
# Include:
# - Current daily spend
# - % of workloads on spot vs standard
# - Spot pricing trends
# - Recommended actions
```

**Escalation:** If cost spike continues >24 hours, notify FinOps team

---

### Runbook 5: VMSS Ghost Instance After Spot Eviction (Node Stuck NotReady/Unknown)

**Alert:** `Node remains NotReady > 5 minutes after eviction` or `VMSS instance in Unknown state`

**Cause:** After spot eviction with `Delete` policy, the VMSS instance fails to clean up properly. The Azure platform marks the instance as Failed/Unknown instead of removing it. The Cluster Autoscaler counts the ghost instance as existing capacity and does not provision a replacement.

**Why no replacement appears in another zone:** Each node pool is backed by one VMSS pinned to specific zones. The autoscaler only provisions within that pool's configured zones. Cross-zone replacement only happens when pending pods trigger the Priority Expander to select a different pool.

**Impact:** Pool capacity is reduced. The ghost node blocks the autoscaler from provisioning a replacement. If pods were running on the evicted node, they become Pending but the autoscaler may not scale up the same pool because it sees the ghost as existing capacity.

**Response Procedure:**

```bash
# Step 1: Identify the ghost node
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o wide
# Look for nodes in "NotReady" or "Unknown" status

# Step 2: Check the VMSS instance state in Azure
# Get the node resource group (MC_* group)
NODE_RG=$(az aks show -g <resource-group> -n <cluster-name> \
  --query nodeResourceGroup -o tsv)

# List VMSS instances and their provisioning states
az vmss list -g $NODE_RG --query "[].name" -o tsv | while read VMSS; do
  echo "=== $VMSS ==="
  az vmss list-instances -g $NODE_RG -n $VMSS \
    --query "[].{name:name, state:provisioningState, zone:zones[0]}" -o table
done
# Look for instances with provisioningState: Failed, Deleting, or Creating

# Step 3: Check autoscaler logs for why it's not replacing
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100 | \
  grep -E "NotReady|unready|failed to delete|ScaleUp"
# Look for: "node is not ready", "failed to delete node", or no ScaleUp entries

# Step 4: Delete the ghost VMSS instance to unblock the autoscaler
# Identify the stuck instance ID from Step 2
az vmss delete-instances -g $NODE_RG -n <vmss-name> --instance-ids <instance-id>

# Step 5: Remove the ghost node from Kubernetes
kubectl delete node <ghost-node-name>
# The autoscaler will now see reduced capacity and provision a replacement

# Step 6: Verify recovery
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -w
# A new node should appear within 2-5 minutes

# Step 7: If the same pool keeps failing (no spot capacity in that zone)
# Check autoscaler logs for capacity errors
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50 | \
  grep -E "CloudProvider|FailedScaleUp|QuotaExceeded"
# If no capacity: pods will schedule on other spot pools or standard pool
# via Priority Expander fallback. No manual action needed.
```

**Automated Mitigations in Place:**

| Mechanism | Setting | What It Does |
|-----------|---------|-------------|
| AKS Node Auto-Repair | Always on | Detects NotReady nodes, attempts reimage/replace |
| `scale_down_unready` | `3m` | Autoscaler removes unready nodes after 3 minutes |
| `max_node_provisioning_time` | `10m` | Autoscaler abandons stuck provisioning after 10 minutes |
| `max_unready_nodes` | `3` | Autoscaler continues scaling even with up to 3 unready nodes |
| Priority Expander | Tiered fallback | Pending pods route to other spot pools or standard pool |

**Expected Timeline With Current Settings:**

```
T+0s:    Spot VM evicted, VMSS instance stuck in Unknown state
T+0s:    Pods from evicted node become Pending
T+20s:   Autoscaler scan detects pending pods
T+20s:   Priority Expander tries same pool → may fail (ghost occupies capacity)
T+40s:   Next scan → Priority Expander tries other spot pools / standard pool
T+120s:  Pods scheduled on different pool (cross-pool fallback works)
T+3m:    scale_down_unready kicks in → autoscaler attempts to delete ghost node
T+5m:    AKS node auto-repair detects NotReady → reimages or replaces instance
T+10m:   max_node_provisioning_time expires → autoscaler marks node as failed
```

**Escalation:** If ghost node persists >15 minutes after manual deletion attempt, open an Azure support ticket -- this indicates a platform-level VMSS issue.

---

### Runbook 5b: Node Not Ready After Eviction (Non-Ghost Scenarios)

**Alert:** `Node remains NotReady > 15 minutes after eviction`

**Cause:** Azure VM provisioning issue, kubelet crash, network issue (not a ghost instance)

**Impact:** Reduced capacity on spot pool

**Response Procedure:**

```bash
# Step 1: Check node status
kubectl describe node <node-name> | grep -A20 Conditions

# Step 2: Check if node is in Azure
NODE_RG=$(az aks show -g <resource-group> -n <cluster-name> \
  --query nodeResourceGroup -o tsv)
az vm list -g $NODE_RG --query "[?name=='<node-name>']"

# If node doesn't exist in Azure:
## Azure failed to provision - this is normal for spot
## Autoscaler will retry, no action needed
## Monitor autoscaler logs:
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=20

# If node exists in Azure but NotReady:
## Check kubelet and network
kubectl get pods -n kube-system -o wide | grep <node-name>

# Step 3: Node unresponsive - drain and delete
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force
kubectl delete node <node-name>
# Autoscaler will replace

# Step 4: Monitor recovery
kubectl get nodes -w
```

---

### Runbook 6: PodDisruptionBudget Violation

**Alert:** `PDB for <deployment> violated - healthy pods < minAvailable`

**Cause:** Too many simultaneous pod disruptions (evictions or rolling updates)

**Impact:** CRITICAL - application below minimum availability

**Response Procedure:**

```bash
# Step 1: IMMEDIATE - Identify affected deployment
kubectl get pdb -A
kubectl describe pdb <pdb-name> -n <namespace>

# Step 2: Check current pod status
kubectl get pods -n <namespace> -l app=<app-label>

# Count Running pods
kubectl get pods -n <namespace> -l app=<app-label> | grep Running | wc -l

# Step 3: IMMEDIATE MITIGATION
# Option A: Manually scale up deployment
kubectl scale deployment <deployment> -n <namespace> --replicas=<current+3>

# Option B: Pause autoscaler temporarily
kubectl annotate deployment <deployment> \
  cluster-autoscaler.kubernetes.io/safe-to-evict=false

# Step 4: Check for ongoing rollout
kubectl rollout status deployment/<deployment> -n <namespace>

# If rollout in progress and causing PDB violation:
kubectl rollout pause deployment/<deployment> -n <namespace>

# Step 5: Verify recovery
watch "kubectl get pdb <pdb-name> -n <namespace>"

# Expected: ALLOWED increases to >0

# Step 6: Root cause analysis
# - Were pods evicted faster than they could be rescheduled?
# - Is minAvailable too aggressive?
# - Do we need more replicas?

# Document findings in incident report
```

**Escalation:** IMMEDIATE escalation to Platform Lead and Application Owner

---

### Runbook 7: Descheduler Not Rebalancing Pods to Spot

**Alert:** `Spot nodes available but >50% of spot-eligible pods remain on standard nodes for >30 minutes`

**Cause:** Descheduler missing, misconfigured, or blocked by PDBs

**Impact:** Financial - pods stuck on expensive standard nodes despite spot capacity being available (sticky fallback)

**Response Procedure:**

```bash
# Step 1: Check if Descheduler is running
kubectl get pods -n kube-system -l app=descheduler
kubectl get cronjob -n kube-system | grep descheduler

# If no pods/cronjobs found:
# Descheduler is NOT installed. See "Install Descheduler" below.

# Step 2: Check Descheduler logs for errors
kubectl logs -n kube-system -l app=descheduler --tail=100

# Look for:
# - "evicted pod" messages (working correctly)
# - "pod can't be evicted" (PDB blocking)
# - "no pods to evict" (policy misconfiguration)

# Step 3: Verify Descheduler policy has correct strategy
kubectl get configmap descheduler-policy -n kube-system -o yaml
# Must contain:
#   RemovePodsViolatingNodeAffinity:
#     enabled: true
#     params:
#       nodeAffinityType:
#         - "preferredDuringSchedulingIgnoredDuringExecution"

# Step 4: Check if PDBs are blocking descheduler evictions
kubectl get pdb -A
# If ALLOWED = 0 for any PDB, descheduler cannot evict those pods
# This is correct behavior - PDBs protect availability

# Step 5: Verify pods have the correct node affinity preference
kubectl get deployment <deployment> -o yaml | grep -A15 "nodeAffinity"
# Must have preferredDuringSchedulingIgnoredDuringExecution
# with weight 100 for spot nodes

# Step 6: Verify spot nodes have capacity
kubectl describe node <spot-node> | grep -A5 "Allocated resources"
# If spot nodes are full, pods can't move there
# Autoscaler should provision more spot nodes for pending pods

# Step 7: Manual rebalance (if descheduler is broken)
# Restart pods one at a time to let scheduler place them on spot
kubectl rollout restart deployment/<deployment> -n <namespace>
# WARNING: This causes brief disruption - use only if descheduler fix is delayed
```

**Install Descheduler (if missing):**

```bash
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler/
helm install descheduler descheduler/descheduler \
  --namespace kube-system \
  --set schedule="*/5 * * * *" \
  --set deschedulerPolicy.strategies.RemovePodsViolatingNodeAffinity.enabled=true \
  --set "deschedulerPolicy.strategies.RemovePodsViolatingNodeAffinity.params.nodeAffinityType[0]=preferredDuringSchedulingIgnoredDuringExecution"
```

**Expected Recovery:**
- T+0m: Descheduler runs (every 5 minutes via CronJob)
- T+0m: Identifies pods on standard nodes that prefer spot
- T+0m: Evicts pods (respecting PDBs)
- T+1m: Scheduler places evicted pods on available spot nodes
- T+5m: Next descheduler cycle handles remaining pods

**Escalation:** If descheduler is running but pods are not moving after 30 minutes, check for PDB deadlocks or insufficient spot capacity. Escalate to Platform Lead if pattern persists.

---

### Runbook 8: Zone or Regional Capacity Exhaustion

**Alert:** `Multiple spot pools failing to provision` or `FailedScaleUp events across 2+ pools`

**Cause:** Azure spot capacity unavailable in one or more availability zones, or region-wide shortage

**Impact:** High - reduced spot capacity, increased cost as workloads shift to standard nodes

**Response Procedure:**

```bash
# Step 1: Determine scope - single zone or regional event
# Check which pools are failing
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=200 | \
  grep -E "FailedScaleUp|CloudProviderError|Quota"

# Check VMSS provisioning errors per pool
NODE_RG=$(az aks show -g <resource-group> -n <cluster-name> \
  --query nodeResourceGroup -o tsv)

az vmss list -g $NODE_RG --query "[].{name:name, capacity:sku.capacity}" -o table

# Step 2: Check Azure spot availability per zone
# Zone 1 pools: spotgeneral1
# Zone 2 pools: spotmemory1, spotgeneral2
# Zone 3 pools: spotmemory2, spotcompute
az vmss list-instances -g $NODE_RG -n <vmss-name> \
  --query "[].{state:provisioningState, zone:zones[0]}" -o table

# Step 3: Check Azure spot pricing and eviction rates
# Azure Portal → Virtual Machines → Pricing → Spot tab
# OR use the Azure Retail Prices API:
curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName eq 'Virtual Machines' and armRegionName eq 'australiaeast' and skuName eq 'D4s v5' and type eq 'Consumption'" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d['Items'][:3], indent=2))"

# Step 4: Assess impact on workloads
kubectl get pods -A --field-selector=status.phase=Pending | wc -l
kubectl get pods -A --field-selector=status.phase=Pending

# Step 5: Decision tree based on scope
```

**Decision Tree:**

```
Capacity Exhaustion Detected
├─ Single zone affected (1 pool failing)
│  ├─ Priority Expander routes to other spot pools automatically
│  ├─ No manual action needed unless pods pending >5 min
│  └─ Monitor: kubectl get pods -A --field-selector=status.phase=Pending
│
├─ Multiple zones affected (2-4 pools failing)
│  ├─ Standard pool should auto-scale via Priority Expander (tier 20)
│  ├─ Verify standard pool is scaling:
│  │  kubectl get nodes -l priority=on-demand
│  ├─ If standard not scaling, manually scale:
│  │  az aks nodepool scale -g <rg> -n <cluster> --name stdworkload --node-count <current+5>
│  └─ Monitor cost impact - notify FinOps if >24h
│
└─ Full region exhaustion (all pools + standard failing)
   ├─ RARE - indicates major Azure capacity event
   ├─ Check Azure Status Page: https://status.azure.com
   ├─ Consider cross-region failover if available
   ├─ Open Azure support ticket (Severity A)
   └─ Escalate to Platform Lead immediately
```

**Recovery Monitoring:**

```bash
# Watch for spot capacity returning
watch -n 60 "kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot | wc -l"

# Check autoscaler for successful scale-ups
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=20 | grep "ScaleUp"
```

**Post-Incident Actions:**
- Review if VM SKU diversity is sufficient (consider adding more families)
- Check if affected zones have chronic capacity issues
- Consider adjusting `spot_max_price` if price-based evictions contributed
- Update capacity planning docs with observed regional patterns

**Escalation:** If all spot AND standard pools fail to provision for >10 minutes, this is a P1 - escalate immediately.

---

### Runbook 9: Autoscaler Stuck in Backoff

**Alert:** `Pending pods >5 minutes with no scale-up activity` or `Autoscaler logs show backoff/retry messages`

**Cause:** Cluster Autoscaler enters exponential backoff after failed scale-up attempts. Common after quota exceeded, VMSS provisioning failures, or transient Azure API errors.

**Impact:** Pods remain pending, application degraded, no new capacity being provisioned

**Response Procedure:**

```bash
# Step 1: Check autoscaler status ConfigMap for backoff state
kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml

# Look for:
# - ScaleUp: "Backoff" or "BackoffLimited"
# - Health: check lastProbeTime and lastTransitionTime
# - NodeGroups: check for "Backoff" entries per pool

# Step 2: Check autoscaler logs for the root cause of backoff
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=200 | \
  grep -E "(backoff|Backoff|retry|failed.*scale|QuotaExceeded|InsufficientCapacity)"

# Common backoff triggers:
# - "failed to increase node group size" → VMSS provisioning failed
# - "QuotaExceeded" → VM quota hit in subscription
# - "AllocationFailed" → No capacity in zone
# - "context deadline exceeded" → Azure API timeout

# Step 3: Check VM quota (common root cause)
az vm list-usage --location australiaeast -o table | \
  grep -E "(Name|DSv5|ESv5|FSv2)" | head -20

# If "CurrentValue" is near "Limit", quota is the issue
# Request increase: Azure Portal → Subscriptions → Usage + quotas

# Step 4: Check VMSS health for the stuck pool
NODE_RG=$(az aks show -g <resource-group> -n <cluster-name> \
  --query nodeResourceGroup -o tsv)

az vmss list -g $NODE_RG -o table
az vmss list-instances -g $NODE_RG -n <stuck-vmss> \
  --query "[].{name:name, state:provisioningState}" -o table

# Step 5: Clear the backoff by resolving the root cause

## If quota exceeded:
# Request quota increase, then wait for backoff to expire
# Backoff duration: starts at ~5min, doubles each failure, caps at ~30min

## If VMSS provisioning stuck:
# Delete stuck instances (see Runbook 5)
az vmss delete-instances -g $NODE_RG -n <vmss-name> --instance-ids <id>

## If Azure API errors (transient):
# Wait for backoff to expire (check autoscaler logs for timer)
# Autoscaler will retry automatically

# Step 6: Force autoscaler to re-evaluate (nuclear option)
# Restart the autoscaler pod to clear all backoff state
kubectl rollout restart deployment cluster-autoscaler -n kube-system
# WARNING: This causes a brief gap in autoscaling (30-60s)
# Only use if backoff is blocking critical workloads

# Step 7: Verify recovery
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=20 | grep "ScaleUp"
kubectl get pods -A --field-selector=status.phase=Pending
```

**Backoff Timeline:**

```
Failure #1: 5 minute backoff for the failed node group
Failure #2: 10 minute backoff
Failure #3: 20 minute backoff
Failure #4+: 30 minute backoff (maximum)
```

Note: Backoff is **per node group** (per pool). If `spotgeneral1` is in backoff, other pools can still scale up normally via Priority Expander fallback.

**Automated Mitigations:**
- Priority Expander automatically tries other pools when one is in backoff
- `max_node_provisioning_time = 10m` prevents indefinite waits for stuck provisioning
- Backoff expires automatically - autoscaler will retry

**Escalation:** If all pools are in backoff simultaneously and pods pending >15 minutes, restart autoscaler (Step 6) and escalate to Platform Lead.

---

### Runbook 10: Node Pool Operations (Day-2)

These are planned operational procedures, not incident response. Use these when making changes to node pool configuration.

#### 10a: Adding a New Spot Pool

**When:** Adding VM SKU diversity, expanding to new zone, increasing capacity

```bash
# Step 1: Add pool definition in Terraform
# Edit: terraform/modules/aks-spot-optimized/node-pools.tf
# Follow naming convention: spotXXXN (lowercase alpha, max 12 chars)
# Example: spotmemory3, spotcompute2

# Step 2: Update Priority Expander ConfigMap
# Edit: terraform/modules/aks-spot-optimized/priority-expander.tf
# Add the new pool regex to the appropriate priority tier:
#   Priority 5: Memory-optimized (E-series) - lowest eviction risk
#   Priority 10: General/compute (D/F-series)

# Step 3: Plan and apply
cd terraform/environments/prod
terraform plan -out=tfplan
# Review: Expect 1 new azurerm_kubernetes_cluster_node_pool resource
# Review: Priority Expander ConfigMap should show new pool regex
terraform apply tfplan

# Step 4: Verify new pool joined cluster
kubectl get nodes -l agentpool=<new-pool-name>

# Step 5: Verify autoscaler recognizes new pool
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50 | grep <new-pool-name>

# Step 6: Verify Priority Expander includes new pool
kubectl get configmap cluster-autoscaler-priority-expander -n kube-system -o yaml
```

#### 10b: Removing a Spot Pool

**When:** Decommissioning VM SKU, consolidating pools, reducing complexity

```bash
# Step 1: Drain workloads from the pool
# Cordon all nodes in the pool to prevent new scheduling
kubectl cordon -l agentpool=<pool-name>

# Drain pods gracefully (respects PDBs)
for node in $(kubectl get nodes -l agentpool=<pool-name> -o name); do
  kubectl drain $node --ignore-daemonsets --delete-emptydir-data --grace-period=60
done

# Step 2: Verify all pods rescheduled
kubectl get pods -A -o wide | grep <pool-name>
# Should return empty - all pods moved to other pools

# Step 3: Remove from Terraform
# Remove pool definition from node-pools.tf
# Remove pool regex from priority-expander.tf

# Step 4: Plan and apply
cd terraform/environments/prod
terraform plan -out=tfplan
# Review: Expect 1 destroyed azurerm_kubernetes_cluster_node_pool
# Review: Updated Priority Expander ConfigMap
terraform apply tfplan

# Step 5: Verify removal
kubectl get nodes -l agentpool=<pool-name>
# Should return: No resources found
```

**WARNING:** Never remove a pool without draining first. Terraform `destroy` on a node pool deletes the VMSS immediately, killing all pods without graceful shutdown.

#### 10c: Resizing Pool Min/Max Node Count

**When:** Adjusting capacity limits based on observed usage

```bash
# Step 1: Update min_count/max_count in Terraform variables
# Edit: terraform/environments/prod/main.tf or terraform.tfvars

# Step 2: Plan and apply
cd terraform/environments/prod
terraform plan -out=tfplan
# Review: Expect in-place update to node pool resource
terraform apply tfplan

# Step 3: Verify autoscaler sees new limits
kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml | \
  grep -A5 <pool-name>
```

**Guidelines:**
- `min_count = 0` for spot pools (allows full scale-down when no spot capacity)
- `min_count >= 2` for standard pool (always-on fallback)
- `min_count = 3` for system pool (HA for control plane components)
- `max_count` should allow 2x expected peak usage per pool

#### 10d: Changing VM SKU for a Pool

**When:** Optimizing for cost, switching to newer VM generation

**IMPORTANT:** VM SKU cannot be changed in-place. You must create a new pool and remove the old one.

```bash
# Step 1: Create new pool with desired SKU (see 10a)
# Use a new name (e.g., spotgeneral1 → spotgeneral1v2)

# Step 2: Wait for new pool to be ready
kubectl get nodes -l agentpool=<new-pool-name> -w

# Step 3: Drain old pool (see 10b)

# Step 4: Remove old pool from Terraform (see 10b)

# Step 5: Optionally rename in next maintenance window
# (Rename requires another create/drain/delete cycle)
```

**Pre-Change Checklist:**
- [ ] Change planned during low-traffic window
- [ ] Terraform plan reviewed by second engineer
- [ ] Priority Expander ConfigMap updated
- [ ] Monitoring dashboards show new pool
- [ ] Rollback plan documented (re-add old pool definition)

---

## Operational Workflows

### Daily Operations Checklist

**Recommended:** Run at start of shift or via scheduled task

```bash
#!/bin/bash
# daily-spot-check.sh

echo "=== Daily AKS Spot Health Check ==="
echo "Date: $(date)"

echo "\n1. Node Status:"
kubectl get nodes -o wide | grep -E "NAME|spot"

echo "\n2. Eviction Count (last 24 hours):"
kubectl get events -A --sort-by='.lastTimestamp' | \
  grep -i evicted | \
  grep -E "$(date +%Y-%m-%d)" | \
  wc -l

echo "\n3. Pending Pods:"
kubectl get pods -A --field-selector=status.phase=Pending | wc -l

echo "\n4. Pod Distribution:"
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
  xargs -I {} kubectl get node {} -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}{"\n"}' 2>/dev/null | \
  sort | uniq -c

echo "\n5. Autoscaler Recent Activity:"
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=10 --since=1h

echo "\n=== Check Complete ==="
```

**Expected Output:**
- All spot nodes: Ready
- Evictions: <50 per day
- Pending pods: 0-2 (transient)
- Distribution: 70-80% spot, 20-30% standard

---

### Weekly Review

**Schedule:** Every Monday, 10:00 AM

**Attendees:** SRE on-call, Platform Engineer, optional FinOps

**Agenda:**

1. **Review Metrics** (15 min)
   - Total evictions last week
   - Average pod pending time
   - Cost variance vs budget
   - Spot adoption %

2. **Incident Review** (10 min)
   - Any P1/P2 incidents related to spot
   - Lessons learned
   - Runbook updates needed

3. **Optimization Opportunities** (10 min)
   - VM size adjustments
   - Workload re-classification (more to spot?)
   - Autoscaler tuning

4. **Action Items** (5 min)
   - Assign owners
   - Set deadlines

---

## Key Metrics & SLOs

### Service Level Objectives

| SLO | Target | Measurement Window | Consequence of Miss |
|-----|--------|-------------------|---------------------|
| **Availability** | 99.9% | 30 days | Post-mortem required |
| **Pod Scheduling Latency** | P95 < 30s | 7 days | Investigation required |
| **Eviction Recovery** | P99 < 120s | 7 days | Runbook review |
| **Cost Savings** | >50% vs baseline | 30 days | FinOps review |

### Metrics to Track

```promql
# Eviction rate (per hour)
rate(kube_pod_status_phase{phase="Failed", reason="Evicted"}[1h])

# Pending pods count
count(kube_pod_status_phase{phase="Pending"})

# Spot vs standard distribution
count(kube_pod_info) by (node)
# Join with node labels for spot/standard classification

# Pod scheduling latency
histogram_quantile(0.95, 
  rate(scheduler_scheduling_duration_seconds_bucket[5m])
)

# Node readiness
kube_node_status_condition{condition="Ready", status="true"}
```

---

## Troubleshooting Guide

### Symptom: Slow Application Response Time

**Diagnosis:**
```bash
# Check if it coincides with eviction event
kubectl get events -A --sort-by='.lastTimestamp' | head -20

# Check pod distribution - are all pods on one node?
kubectl get pods -n <namespace> -o wide

# Check node resources
kubectl top nodes
```

**Likely Causes:**
1. Pod affinity caused all pods to land on single node during eviction
2. Insufficient replicas
3. Topology spread maxSkew too high

**Fix:**
- Adjust topology spread constraints
- Increase replica count
- Review pod affinity rules

---

### Symptom: Autoscaler Not Scaling Up Spot Pools

**Diagnosis:**
```bash
# Check autoscaler logs for errors
kubectl logs -n kube-system -l app=cluster-autoscaler | grep -i error

# Check if spot pool is at max capacity
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot | wc -l
# Compare to max_count in Terraform

# Check Azure spot pricing
az vm list-skus --location australiaeast --size Standard_D --all --output table | grep Spot
```

**Likely Causes:**
1. Spot pool at max_count - increase limit
2. No spot capacity in Azure - wait or use different VM size
3. Autoscaler disabled for pool - check configmap

**Fix:**
- Increase max_count if intentionally limited
- Wait for spot capacity (typically <30 mins)
- Verify priority expander falls back to standard

---

## Incident Response

### P1 Incident: Multiple Application Outage Due to Eviction

**Immediate Actions (first 5 minutes):**
1. Join #incident-spot-nodes channel
2. Verify if this is spot-related:
   ```bash
   kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot
   ```
3. Check affected applications
4. Manual scale-up standard pool if not auto-scaling:
   ```bash
   az aks nodepool scale --resource-group rg-aks-prod \
     --cluster-name aks-prod --name stdworkload --node-count 15
   ```
5. Update status page

**Next Steps (5-30 minutes):**
- Monitor pod rescheduling
- Verify application recovery
- Document timeline
- Identify root cause

**Follow-up (after resolution):**
- Conduct blameless post-mortem
- Update runbooks
- Consider architecture adjustments

---

## On-Call Handoff

### Information to Share

When handing off on-call rotation:

1. **Active Issues**
   - Any ongoing eviction patterns
   - Pods that had prolonged pending states
   - Cost anomalies

2. **Recent Changes**
   - Terraform applied in last 24 hours
   - Deployments to production
   - Autoscaler config changes

3. **Monitoring Status**
   - Any flapping alerts (acknowledged but unresolved)
   - Known issues with dashboards

4. **Context**
   - Current spot adoption %
   - Recent incident history
   - Scheduled maintenance

---

## Tools & Resources

### Essential Tools

| Tool | Purpose | Access |
|------|---------|--------|
| kubectl | Cluster interaction | Local CLI |
| az CLI | Azure resources | Local CLI |
| Grafana | Monitoring dashboards | https://grafana.company.com |
| PagerDuty | Alerting | Mobile app |
| Slack | Communication | #platform-engineering, #sre |

### Reference Links

- [Troubleshooting Guide](TROUBLESHOOTING_GUIDE.md) - Symptom-first diagnostic reference
- [Migration Guide](MIGRATION_GUIDE.md) - Converting existing clusters to spot
- [AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Spot VMs Best Practices](https://docs.microsoft.com/en-us/azure/virtual-machines/spot-vms)
- [Cluster Autoscaler FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
- [Internal Wiki: AKS Architecture](https://wiki.company.com/aks-architecture)

---

## Training & Onboarding

### New SRE Checklist

- [ ] Review this runbook
- [ ] Review architecture document
- [ ] Shadow existing SRE during on-call shift
- [ ] Run through Runbooks 1-3 in dev environment
- [ ] Access to all dashboards confirmed
- [ ] PagerDuty escalation policy verified
- [ ] Completed chaos engineering walkthrough

**Training Lab:** `dev-aks-cluster` has spot pools for practice.

---

**Document Maintenance**

This runbook should be reviewed and updated:
- After every P1/P2 incident involving spot nodes
- Monthly during SRE team meeting
- When architecture changes are deployed

**Last Review:** 2026-01-12  
**Next Review Due:** 2026-02-12

---

**On-Call Support**

Questions? Contact:
- **Platform Team:** #platform-engineering (Slack)
- **On-Call Engineer:** Check PagerDuty rotation
- **Emergency Escalation:** Platform Lead (see PagerDuty)
