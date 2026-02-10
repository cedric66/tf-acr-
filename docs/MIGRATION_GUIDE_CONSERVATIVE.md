# Conservative Migration Guide: 40% Spot Target

**Audience:** Cloud Operations and Application Teams seeking a lower-risk approach
**Purpose:** Simplified spot migration with 3 pools and 40% target
**Timeline:** 3-4 weeks
**Last Updated:** 2026-02-10

> **Is this guide right for you?** See [Quick Start Decision](#quick-start-decision) below. For advanced configuration (5+ pools, 70%+ target), see [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md).

---

## Table of Contents

1. [Quick Start Decision](#quick-start-decision)
2. [Architecture Overview](#architecture-overview)
3. [Step 1: Pre-Check](#step-1-pre-check-5-min)
4. [Step 2: Add 3 Spot Pools](#step-2-add-3-spot-pools-1-day)
5. [Step 3: Migrate One Workload](#step-3-migrate-one-workload-1-week)
6. [Step 4: Expand Gradually](#step-4-expand-gradually-2-3-weeks)
7. [Troubleshooting](#troubleshooting)
8. [Rollback](#rollback)

---

## Quick Start Decision

| Your Situation | Use This Guide |
|----------------|----------------|
| < 100 nodes, want quick cost savings | ✅ This guide |
| Can tolerate ~5% eviction risk | ✅ This guide |
| Want minimal operational changes | ✅ This guide |
| > 200 nodes or >70% savings target | ❌ Use [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) |
| Complex workload mix (GPU, stateful, batch) | ❌ Use [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) |
| Need custom VM families per region | ❌ Use [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) |

**Expected Savings:** ~40% on compute costs (vs ~50-70% with main guide)

**Key Differences:**

| Aspect | This Guide | Main Guide |
|--------|------------|------------|
| Spot Target | 40% | 70% |
| Pools | 3 (fixed) | 3-7 (configurable) |
| VM Families | D + E only | D + E + F (expandable) |
| Standard Fallback | 60% of capacity | 30% of capacity |
| Eviction Risk | ~2-4% | <1% with 5+ pools |
| Timeline | 3-4 weeks | 6-8 weeks |

---

## Architecture Overview

### 3 Pool Design

```
┌─────────────────────────────────────────────────────────────┐
│                    Your AKS Cluster                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  System Pool (on-demand)                                     │
│  └─ Runs control-plane components                            │
│                                                              │
│  Standard Pool (on-demand, 60% capacity)                     │
│  └─ Absorbs evictions, runs non-spot workloads              │
│                                                              │
│  Spot Pools (40% capacity)                                   │
│  ├─ Pool 1: Standard_E4s_v5 (memory-optimized, zone 1)      │
│  ├─ Pool 2: Standard_D4s_v5 (general-purpose, zone 2)       │
│  └─ Pool 3: Standard_D8s_v5 (general-purpose, zone 3)       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Pool Configuration

| Pool | VM Size | vCPUs | Memory | Zone | Priority | Max Nodes |
|------|---------|-------|--------|------|----------|-----------|
| **spotmemory1** | Standard_E4s_v5 | 4 | 32 GB | 1 | 5 (highest) | 10 |
| **spotgeneral1** | Standard_D4s_v5 | 4 | 16 GB | 2 | 10 | 10 |
| **spotgeneral2** | Standard_D8s_v5 | 8 | 32 GB | 3 | 10 | 10 |

**Why these choices:**

- **E-series (memory)**: Lowest historical eviction rate per [Azure AKS Team](https://blog.aks.azure.com/2025/07/17/Scaling-safely-with-spot-on-aks)
- **D-series (general)**: Balanced cost/performance, wide availability
- **3 zones**: Reduces correlated eviction risk across pools
- **Max 10 per pool**: Conservative sizing, easier quota approval

### Priority Expander (How Pools Are Selected)

Lower number = higher preference:

```
Priority 5  → spotmemory1 (E-series)    ← Preferred first
Priority 10 → spotgeneral1 (D-series)   ← Backup
Priority 10 → spotgeneral2 (D-series)   ← Backup
Priority 20 → Standard (on-demand)      ← Fallback
Priority 30 → System (never for workloads)
```

---

## Step 1: Pre-Check (5 min)

### Cluster Compatibility

```bash
# Set your cluster details
CLUSTER_NAME="your-cluster-name"
RESOURCE_GROUP="your-resource-group"

# Check cluster version and autoscaler status
az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --query "{
    k8sVersion: kubernetesVersion,
    location: location,
    autoScaler: autoScalerProfile.expander
  }" -o table
```

**Requirements:**

| Check | Command | Minimum |
|-------|---------|---------|
| Kubernetes version | `az aks show --query kubernetesVersion` | >= 1.28 |
| Cluster Autoscaler | `az aks show --query autoScalerProfile` | Must exist |
| Node pool type | `az aks nodepool list --query "[].type"` | VMSS |

If any check fails, your cluster needs upgrades before proceeding.

### Quota Check

```bash
# Get cluster location
LOCATION=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query location -o tsv)

# Check VM quota (need ~120 vCPUs for 3 pools)
az vm list-usage --location $LOCATION -o table | grep -E "Total Regional vCPUs"

# Check specific SKU availability
for sku in "Standard_E4s_v5" "Standard_D4s_v5" "Standard_D8s_v5"; do
  echo "Checking $sku:"
  az vm list-skus --location $LOCATION --resource-type virtualMachines \
    --query "[?name=='$sku'].restrictions | [0]" -o json 2>/dev/null
done
```

**Required:** At least 120 vCPU quota available in target region.

---

## Step 2: Add 3 Spot Pools (1 day)

> **Risk:** LOW - Adding pools does not affect existing workloads

### 2.1 Update Autoscaler Profile

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

### 2.2 Add the 3 Spot Pools

```bash
# Pool 1: Memory-optimized (priority 5, preferred)
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --name spotmemory1 \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --node-count 0 \
  --min-count 0 \
  --max-count 10 \
  --enable-cluster-autoscaler \
  --node-vm-size Standard_E4s_v5 \
  --zones 1 \
  --labels workload-type=spot vm-family=memory cost-optimization=spot-enabled \
  --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"

# Pool 2: General-purpose zone 2 (priority 10)
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --name spotgeneral1 \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --node-count 0 \
  --min-count 0 \
  --max-count 10 \
  --enable-cluster-autoscaler \
  --node-vm-size Standard_D4s_v5 \
  --zones 2 \
  --labels workload-type=spot vm-family=general cost-optimization=spot-enabled \
  --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"

# Pool 3: General-purpose zone 3 (priority 10)
az aks nodepool add \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --name spotgeneral2 \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --node-count 0 \
  --min-count 0 \
  --max-count 10 \
  --enable-cluster-autoscaler \
  --node-vm-size Standard_D8s_v5 \
  --zones 3 \
  --labels workload-type=spot vm-family=general cost-optimization=spot-enabled \
  --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
```

### 2.3 Deploy Priority Expander

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
    10:
      - .*spotgeneral1.*
      - .*spotgeneral2.*
    20:
      - .*stdworkload.*
    30:
      - .*system.*
EOF
```

### 2.4 Verify

```bash
# Check all 3 pools exist
az aks nodepool list -g $RESOURCE_GROUP -n $CLUSTER_NAME \
  --query "[?scaleSetPriority=='Spot'].{name:name, vmSize:vmSize, maxCount:maxCount}" \
  -o table

# Check Priority Expander
kubectl get configmap cluster-autoscaler-priority-expander -n kube-system -o yaml

# Verify autoscaler sees pools
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50 | grep -E "spotmemory|spotgeneral"
```

**Expected output:** 3 spot pools listed, all with 0 current nodes (will scale when workloads request spot)

---

## Step 3: Migrate One Workload (1 week)

> **Goal:** Validate spot behavior with a single low-risk workload before expanding

### 3.1 Choose a Pilot Workload

Pick a deployment that is:
- Low business impact if degraded
- Has 3+ replicas (for high availability)
- Already has health checks (readiness/liveness probes)
- Not stateful (no PVCs)

```bash
# List deployments with replica counts
kubectl get deployments -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,REPLICAS:.spec.replicas
```

### 3.2 Backup Current Deployment

```bash
NAMESPACE="your-namespace"
DEPLOYMENT="your-deployment-name"

kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o yaml > backup-$DEPLOYMENT.yaml
```

### 3.3 Add Spot Configuration

> **Tip:** For complete deployment templates with graceful shutdown, PDBs, and health checks, see [DEVOPS_TEAM_GUIDE.md](DEVOPS_TEAM_GUIDE.md) Method 2: Full Optimization.

Create a new file or patch your deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-deployment-name
  namespace: your-namespace
spec:
  template:
    spec:
      # Allow scheduling on spot nodes
      tolerations:
        - key: kubernetes.azure.com/scalesetpriority
          operator: Equal
          value: spot
          effect: NoSchedule

      # Prefer spot, accept standard as fallback
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.azure.com/scalesetpriority
                    operator: In
                    values: [spot]

      # Spread across zones and node types
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: your-app-label
        - maxSkew: 1
          topologyKey: kubernetes.azure.com/scalesetpriority
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: your-app-label

      # Graceful shutdown handling
      terminationGracePeriodSeconds: 35
      containers:
        - name: your-container
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 25"]
```

### 3.4 Apply and Watch

```bash
# Apply the updated deployment
kubectl apply -f deployment-spot.yaml -n $NAMESPACE

# Watch rollout
kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE --timeout=5m

# Verify pod placement
kubectl get pods -n $NAMESPACE -l app=your-app-label -o wide
```

### 3.5 Verify Pods on Spot

```bash
# Check which nodes pods are on
for pod in $(kubectl get pods -n $NAMESPACE -l app=your-app-label -o name); do
  node=$(kubectl get $pod -n $NAMESPACE -o jsonpath='{.spec.nodeName}')
  priority=$(kubectl get node $node \
    -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}' 2>/dev/null \
    || echo "unknown")
  echo "$pod → $node ($priority)"
done
```

### 3.6 Test Eviction Resilience (Optional)

```bash
# Simulate eviction by draining a spot node
SPOT_NODE=$(kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o name | head -1)
kubectl drain $SPOT_NODE --ignore-daemonsets --delete-emptydir-data --grace-period=60

# Watch pods reschedule
kubectl get pods -n $NAMESPACE -l app=your-app-label -w

# Uncordon when done
kubectl uncordon $SPOT_NODE
```

### 3.7 Monitor for 1 Week

Track these metrics:

| Metric | Target | How to Check |
|--------|--------|--------------|
| Availability | >= 99.9% | Your monitoring |
| Pods on spot | >= 40% | `kubectl get pods -o wide` |
| Eviction recovery | < 60s | `kubectl get events` |

---

## Step 4: Expand Gradually (2-3 weeks)

> **Pilot successful?** Now migrate remaining workloads at your own pace

### 4.1 Migrate Additional Workloads

For each workload, repeat Step 3:

1. Backup deployment
2. Add spot toleration/affinity
3. Apply and verify
4. Monitor for 24-48 hours

**Recommended order:**

| Week | Workloads | Risk |
|------|-----------|------|
| 1 | Dev/test environments | Low |
| 2 | Internal tools, batch jobs | Medium |
| 3 | Production non-critical | Medium |
| 4+ | Production user-facing | Higher |

### 4.2 Check Migration Progress

```bash
# Spot adoption percentage
TOTAL_PODS=$(kubectl get pods -A --no-headers | wc -l)
SPOT_PODS=$(kubectl get pods -A -o json | \
  jq -r '.items[] | select(.spec.nodeName != null) | .spec.nodeName' | \
  xargs -I {} kubectl get node {} -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}' | \
  grep -c spot || echo 0)

echo "Spot adoption: $(echo "scale=1; $SPOT_PODS * 100 / $TOTAL_PODS" | bc)%"
```

### 4.3 Workloads to Exclude

**Never migrate these to spot:**

- StatefulSets with PVCs (databases, queues)
- Singleton deployments (only 1 replica)
- Compliance-regulated workloads (PCI, HIPAA)
- Long-running connections without drain handling

**Protect them with anti-affinity:**

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.azure.com/scalesetpriority
              operator: NotIn
              values: [spot]
```

### 4.4 Optional: Install Descheduler

After evictions, pods can get "stuck" on standard nodes. The Descheduler moves them back to spot when capacity recovers.

```bash
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler/
helm install descheduler descheduler/descheduler \
  --namespace kube-system \
  --set schedule="*/10 * * * *" \
  --set deschedulerPolicy.strategies.RemovePodsViolatingNodeAffinity.enabled=true \
  --set "deschedulerPolicy.strategies.RemovePodsViolatingNodeAffinity.params.nodeAffinityType[0]=preferredDuringSchedulingIgnoredDuringExecution"
```

---

## Troubleshooting

### Pods Not Scheduling on Spot

**Symptom:** Pods staying on standard nodes despite spot toleration

**Checks:**

```bash
# 1. Verify toleration exists
kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.template.spec.tolerations}' | jq .

# 2. Check spot nodes are schedulable
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot

# 3. Check for taints
kubectl describe node <spot-node-name> | grep Taints

# 4. Verify autoscaler is creating spot nodes
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100 | grep -i scale
```

**Common fixes:**
- Ensure `node-count` is not at max in spot pools
- Check quota limits
- Verify SKU availability in your region

### High Eviction Rate

**Symptom:** Frequent pod restarts from spot nodes

**Check:**

```bash
# Count evictions in last hour
kubectl get events -A --field-selector reason=Evicted --since=1h | wc -l
```

**If >5 evictions/hour:**
1. Check Azure capacity status for your region
2. Consider switching to different VM SKUs (see main guide)
3. Temporarily cordon spot nodes: `kubectl cordon -l kubernetes.azure.com/scalesetpriority=spot`

### Pods Pending

**Symptom:** Pods stuck in Pending state

**Check:**

```bash
kubectl describe pod <pending-pod> -n $NAMESPACE
```

**Look for:**
- `Insufficient vcpus` → Increase pool max or check quota
- `node(s) had taint {spot: NoSchedule}` → Add toleration
- `0/3 nodes are available` → Standard pool at max, increase it

---

## Rollback

### Per-Workload Rollback

```bash
# Restore original deployment
kubectl apply -f backup-$DEPLOYMENT.yaml -n $NAMESPACE

# Verify pods moved to standard
kubectl get pods -n $NAMESPACE -o wide
```

### Pause New Spot Scheduling

```bash
# Prevent new pods from going to spot
kubectl cordon -l kubernetes.azure.com/scalesetpriority=spot

# Resume when ready
kubectl uncordon -l kubernetes.azure.com/scalesetpriority=spot
```

### Remove All Spot Pools

```bash
# Step 1: Cordon all spot nodes
kubectl cordon -l kubernetes.azure.com/scalesetpriority=spot

# Step 2: Drain all spot nodes
for node in $(kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o name); do
  kubectl drain $node --ignore-daemonsets --delete-emptydir-data --grace-period=60
done

# Step 3: Remove pools
for pool in spotmemory1 spotgeneral1 spotgeneral2; do
  az aks nodepool delete -g $RESOURCE_GROUP -n $CLUSTER_NAME \
    --nodepool-name $pool
done

# Step 4: Remove Priority Expander
kubectl delete configmap cluster-autoscaler-priority-expander -n kube-system

# Step 5: Remove spot tolerations from workloads
# (Apply backup YAMLs for each migrated workload)
```

---

## When to Use the Main Guide

Consider upgrading to [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) if:

- ✅ You want 70%+ spot adoption (higher savings)
- ✅ You have >200 nodes (need more pools)
- ✅ You want to add F-series (compute) or Arm64 VMs
- ✅ You need region-specific SKU customization
- ✅ You want comprehensive rollout playbooks

**Main guide features:**
- 5-7 configurable pools
- Customizable VM families per pool
- Detailed quota planning worksheets
- Communication templates
- Fleet rollout strategy for multi-cluster

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) | Full-featured migration (5+ pools, 70% target) |
| [DEVOPS_TEAM_GUIDE.md](DEVOPS_TEAM_GUIDE.md) | Application spot configuration templates |
| [SRE Operational Runbook](SRE_OPERATIONAL_RUNBOOK.md) | Incident response procedures |
| [Troubleshooting Guide](TROUBLESHOOTING_GUIDE.md) | Symptom-first diagnostics |

---

**Last Updated:** 2026-02-10
**Status:** Ready for use
