# Fleet Rollout Strategy: Spot Optimization for 300+ Clusters

**Target Scale:** 300+ AKS Clusters  
**Scope:** Fleet-wide adoption of Spot Node Architecture  
**Document Version:** 1.0

---

## ⚠️ Critical Fleet Risks (The "Fail at Scale" Scenarios)

### 1. The "Spot Cannibalization" Effect
**Scenario:** 
- You deploy this architecture to 300 clusters in `australiaeast`.
- Suddenly, your own clusters demand 3,000+ spot nodes of `Standard_D4s_v5`.
- **Result:** You artificially spike the spot price or exhaust the capacity in that region. Your clusters start evicting *each other* or failing to scale.
**Mitigation:**
- **VM Diversity:** Enforce DIFFERENT spot VM sizes for different clusters (e.g., Cluster Set A uses `D4s`, Cluster Set B uses `E4s`).
- **Subscription Sharding:** Ensure clusters are spread across multiple Azure Subscriptions to avoid hitting the "Regional Spot vCPU Quota" (typically 2,000-10,000 vCPUs per subscription).

### 2. Simultaneous Regional Eviction (Global Outage)
**Scenario:** 
- A major Azure capacity event occurs in `australiaeast`.
- Azure reclaims spot capacity across the entire region.
- **Impact:** All 300 clusters lose their spot pools simultaneously.
- **Result:** 
  - Massive spike in standard node requests (3,000+ nodes). 
  - Azure **Standard** allocation might fail due to sudden surge (AllocationFailed).
  - Your critical fallback mechanism fails because the cloud provider can't fulfill the standard fallback fast enough.
**Mitigation:**
- **Oversized Standard Pools:** Maintain a higher "minimum" standard count (buffer) on critical clusters.
- **Region Diversification:** If possible, enable DR clusters in `australiasoutheast` or paired regions.

### 3. Management Plane Saturation (ARM Throttling)
**Scenario:**
- 300 clusters autoscaling simultaneously (e.g., 9 AM login storm).
- Thousands of `VirtualMachineScaleSet` API calls hit Azure Resource Manager.
- **Result:** HTTP 429 Throttling. Autoscalers hang. Nodes don't provision.
**Mitigation:**
- **Autoscaler Tuning:** Randomize `scan_interval` across the fleet (e.g., spread between 10s and 60s).

---

## 🗺️ Rollout Strategy: The "Wave" Approach

**Do not deploy to all 300 clusters at once.** Use a 4-Wave approach.

### Wave 0: The "PoC" (Current State)
- **Scope:** 1 Non-Prod Cluster + 1 Prod Canary.
- **Goal:** Validate the architecture (templates, affinity rules).
- **Duration:** 2 Weeks.

### Wave 1: "Development Fleet"
- **Scope:** All Dev/Test/Staging clusters (~100 clusters).
- **Goal:** Stress test Spot availability. "Cannibalization" check.
- **Safety:** PDBs enabled, but aggressive spot usage (100% capacity).
- **Duration:** 4 Weeks.

### Wave 2: "Production Non-Critical"
- **Scope:** Production clusters for internal tools, batch processing (~50 clusters).
- **Goal:** Validate "Standard Fallback" in anger.
- **Safety:** Priority Expander enabled.
- **Duration:** 4 Weeks.

### Wave 3: "Production Core" (The Big One)
- **Scope:** Business critical clusters (~150 clusters).
- **Strategy:** Broken into batches of 10 clusters per day.
- **Safety:** Detailed monitoring of "AllocationFailed" events.

---

## 🏰 Governance & Policy (How to Manage 300 Clusters)

You cannot manually check 300 clusters. You need **Azure Policy**.

### 1. Enforce PDBs (Resilience)
Create an Azure Policy to **Audit/Deny** any deployment that:
- Has `replicas > 1`
- But is MISSING a `PodDisruptionBudget`.
*Reason: PDBs are the only thing saving you during mass eviction.*

### 2. Enforce Anti-Affinity (Data Safety)
Create an Azure Policy to **Deny** StatefulSets that do NOT have `nodeAffinity` excluding spot nodes.
*Reason: Prevents a developer from accidentally deploying a database to a cheap spot node on Cluster #142.*

### 3. Enforce Terraform Module Version
Use strict version pinning on your Terraform module source.
- Update fleet to `v1.0.1` -> Apply to Wave 1.
- Verify -> Apply to Wave 2.

---

## 📊 Fleet Observability (Aggregated Metrics)

**Problem:** You cannot look at 300 Grafana dashboards.
**Solution:** Build a "Fleet Health" Dashboard using Thanos/Cortex (Federated Prometheus) or Azure Monitor Workbooks.

**Key Aggregate Metrics:**
1. **Global Savings Rate:** Total $ saved across fleet.
2. **Global Eviction Rate:** Are we seeing a regional storm? (Evictions > 1000/hour fleet-wide).
3. **Fallback Rate:** % of clusters currently running on Standard fallback (indicates Spot exhaustion).

---

## ✅ Checklist for 300-Cluster Success

1. [ ] **Quota Check:** tally up total vCPUs needed. Split across subscriptions to ensure quotas allow full fallback to Standard.
2. [ ] **Automation:** Ensure CI/CD pipelines can apply Terraform to batches of clusters (GitOps/ArgoCD).
3. [ ] **Governance:** Deploy Azure Policy to prevent "Stateful-on-Spot".
4. [ ] **Training:** Train the 50+ dev teams using these clusters on "Graceful Shutdown".

---
**Status:** Rollout Strategy Defined. Focus shifts from "Node Mechanics" to "Fleet Governance".
