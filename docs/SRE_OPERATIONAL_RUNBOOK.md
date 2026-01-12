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

### Runbook 5: Node Not Ready After Eviction Recovery

**Alert:** `Node remains NotReady > 15 minutes after eviction`

**Cause:** Azure VM provisioning issue, kubelet crash, network issue

**Impact:** Reduced capacity on spot pool

**Response Procedure:**

```bash
# Step 1: Check node status
kubectl describe node <node-name> | grep -A20 Conditions

# Step 2: Check if node is in Azure
az vm list -g <node-resource-group> --query "[?name=='<node-name>']"

# If node doesn't exist in Azure:
## Azure failed to provision - this is normal for spot
## Autoscaler will retry, no action needed
## Monitor autoscaler logs:
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=20

# If node exists in Azure but NotReady:
## SSH to node (if possible) and check kubelet
ssh azureuser@<node-ip>
sudo systemctl status kubelet
sudo journalctl -u kubelet --no-pager | tail -50

# Step 3: Common fixes
## Fix 1: Kubelet crash - restart
ssh azureuser@<node-ip> "sudo systemctl restart kubelet"

## Fix 2: Network issue - check CNI
kubectl get pods -n kube-system -o wide | grep <node-name>

## Fix 3: Node unresponsive - drain and delete
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <node-name>
# Autoscaler will replace

# Step 4: Monitor recovery
kubectl get node <node-name> -w
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
