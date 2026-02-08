# AKS Spot Node Behavior Test Scenarios

Manual test specification for validating AKS Spot VM behavior with Robot-Shop workload.

> **📖 See [README.md](README.md) for setup instructions and how to run these tests.**
>
> **⚙️ Configuration**: The values below are **reference examples**. Replace with your actual cluster details:
> 1. Copy `.env.example` to `.env`
> 2. Edit with your cluster name, resource group, and namespace
> 3. Load: `source .env`
> 4. Use `$CLUSTER_NAME`, `$RESOURCE_GROUP`, `$NAMESPACE` in commands instead of hardcoded values

## Environment

| Setting | Value |
|---------|-------|
| Cluster | `aks-spot-prod` |
| Resource Group | `rg-aks-spot` |
| Namespace | `robot-shop` |
| Kubernetes | 1.28+ |
| Workload | Robot-Shop (12 services) |

## Node Pool Configuration

| Pool | VM SKU | Zone(s) | Min/Max | Type | Priority Weight |
|------|--------|---------|---------|------|-----------------|
| system | Standard_D4s_v5 | 1,2,3 | 3-6 | System | 30 |
| stdworkload | Standard_D4s_v5 | 1,2 | 2-10 | On-Demand | 20 |
| spotgeneral1 | Standard_D4s_v5 | 1 | 0-20 | Spot | 10 |
| spotmemory1 | Standard_E4s_v5 | 2 | 0-15 | Spot | 5 |
| spotgeneral2 | Standard_D8s_v5 | 2 | 0-15 | Spot | 10 |
| spotcompute | Standard_F8s_v2 | 3 | 0-10 | Spot | 10 |
| spotmemory2 | Standard_E8s_v5 | 3 | 0-10 | Spot | 5 |

## Service Placement

| Placement | Services |
|-----------|----------|
| Stateless (Spot) | web, cart, catalogue, user, payment, shipping, ratings, dispatch |
| Stateful (Standard) | mongodb, mysql, redis, rabbitmq |

## PDB Coverage

All `minAvailable: 1`: web, cart, catalogue, mongodb, mysql, redis, rabbitmq

## Estimated Duration

| Category | Tests | Duration |
|----------|-------|----------|
| 01 Pod Distribution | 10 | 5 min |
| 02 Eviction Behavior | 10 | 15 min |
| 03 PDB Enforcement | 6 | 10 min |
| 04 Topology Spread | 5 | 8 min |
| 05 Recovery & Rescheduling | 6 | 12 min |
| 06 Sticky Fallback | 5 | 10 min |
| 07 VMSS & Node Pool | 6 | 5 min |
| 08 Autoscaler | 5 | 15 min |
| 09 Cross-Service | 5 | 10 min |
| 10 Edge Cases | 5 | 15 min |
| **Total** | **63** | **~105 min** |

---

## Category 1: Pod Distribution (Read-Only)

### DIST-001: Stateless services on spot nodes
**Type:** Read-only | **Duration:** 1 min

**Objective:** Verify all 8 stateless services have pods running on spot nodes.

**Steps:**
1. For each stateless service: `kubectl get pods -n robot-shop -l app=<svc> -o wide`
2. For each pod's node: `kubectl get node <node> -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}'`
3. Verify the label is `spot`

**Expected Results:**
- [ ] web has >= 1 pod on a spot node
- [ ] cart has >= 1 pod on a spot node
- [ ] catalogue has >= 1 pod on a spot node
- [ ] user has >= 1 pod on a spot node
- [ ] payment has >= 1 pod on a spot node
- [ ] shipping has >= 1 pod on a spot node
- [ ] ratings has >= 1 pod on a spot node
- [ ] dispatch has >= 1 pod on a spot node

**Evidence:** Pod-to-node mapping per service

---

### DIST-002: Stateful services not on spot nodes
**Type:** Read-only | **Duration:** 1 min

**Objective:** Verify stateful services have zero pods on spot nodes.

**Steps:**
1. For each stateful service: `kubectl get pods -n robot-shop -l app=<svc> -o wide`
2. Verify node does NOT have label `kubernetes.azure.com/scalesetpriority=spot`

**Expected Results:**
- [ ] mongodb has 0 pods on spot nodes
- [ ] mysql has 0 pods on spot nodes
- [ ] redis has 0 pods on spot nodes
- [ ] rabbitmq has 0 pods on spot nodes

---

### DIST-003: Spot tolerations present
**Type:** Read-only | **Duration:** 1 min

**Objective:** Verify stateless pods tolerate the spot NoSchedule taint.

**Steps:**
1. `kubectl get pod <stateless-pod> -n robot-shop -o jsonpath='{.spec.tolerations}'`
2. Look for: `key=kubernetes.azure.com/scalesetpriority, value=spot, effect=NoSchedule`

**Expected Results:**
- [ ] All 8 stateless services have the spot toleration

---

### DIST-004: Node affinity preference (weight 100 spot, weight 50 on-demand)
**Type:** Read-only | **Duration:** 1 min

**Objective:** Verify stateless pods prefer spot nodes with weight 100.

**Steps:**
1. `kubectl get pod <pod> -n robot-shop -o jsonpath='{.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution}'`
2. Verify weight=100 for spot preference
3. Verify weight=50 for on-demand fallback

**Expected Results:**
- [ ] Spot preference weight >= 100
- [ ] On-demand fallback weight = 50

---

### DIST-005: Stateful anti-spot required affinity
**Type:** Read-only | **Duration:** 1 min

**Objective:** Verify stateful pods have `requiredDuringScheduling` with `NotIn spot`.

**Steps:**
1. `kubectl get pod <stateful-pod> -n robot-shop -o jsonpath='{.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution}'`
2. Verify `matchExpressions` contains `key=kubernetes.azure.com/scalesetpriority, operator=NotIn, values=[spot]`

**Expected Results:**
- [ ] All 4 stateful services have required anti-spot affinity

---

### DIST-006: System pool protected from user workloads
**Type:** Read-only | **Duration:** 1 min

**Objective:** No user application pods scheduled on system pool nodes.

**Steps:**
1. `kubectl get nodes -l agentpool=system -o name`
2. For each: `kubectl get pods --all-namespaces --field-selector spec.nodeName=<node>`
3. Verify only system namespaces (kube-system, etc.)

**Expected Results:**
- [ ] Zero pods from `robot-shop` namespace on system nodes

---

### DIST-007: Pod diversity across spot pools
**Type:** Read-only | **Duration:** 1 min

**Objective:** Pods are distributed across at least 2 of 5 spot pools.

**Steps:**
1. `kubectl get pods -n robot-shop -o wide`
2. Map each pod's node to its `agentpool` label
3. Count unique spot pools hosting pods

**Expected Results:**
- [ ] Pods on >= 2 different spot pools

---

### DIST-008: Zone spread
**Type:** Read-only | **Duration:** 1 min

**Objective:** Pods distributed across at least 2 availability zones, no zone > 60%.

**Steps:**
1. For each pod, get node's `topology.kubernetes.io/zone` label
2. Count pods per zone
3. Calculate zone percentages

**Expected Results:**
- [ ] Pods in >= 2 zones
- [ ] No single zone has > 60% of pods

---

### DIST-009: Topology spread constraints applied
**Type:** Read-only | **Duration:** 1 min

**Objective:** Stateless pods have zone topology spread with `ScheduleAnyway`.

**Steps:**
1. `kubectl get pod <pod> -n robot-shop -o jsonpath='{.spec.topologySpreadConstraints}'`
2. Verify `topologyKey=topology.kubernetes.io/zone`
3. Verify `whenUnsatisfiable=ScheduleAnyway`

**Expected Results:**
- [ ] Zone TSC present on all stateless services
- [ ] `whenUnsatisfiable=ScheduleAnyway`

---

### DIST-010: Spot vs on-demand ratio
**Type:** Read-only | **Duration:** 1 min

**Objective:** >= 50% of user workload pods on spot nodes (target: 75%).

**Steps:**
1. Count all pods in `robot-shop` namespace
2. Classify each by node type (spot/standard/system)
3. Calculate spot % of user workloads (exclude system)

**Expected Results:**
- [ ] Spot ratio >= 50% of user workload pods

---

## Category 2: Eviction Behavior (Destructive)

### EVICT-001: Single node drain reschedules pods
**Type:** Destructive | **Duration:** 3 min

**Objective:** Draining 1 spot node causes pods to reschedule to other nodes.

**Prerequisites:** At least 1 spot node with pods

**Steps:**
1. Record pods on target spot node
2. `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force`
3. Wait for pods to become Running
4. Verify no user pods remain on drained node

**Expected Results:**
- [ ] All displaced pods reschedule to other nodes
- [ ] Total running pod count recovers

**Rollback:** `kubectl uncordon <node>`

---

### EVICT-002: Graceful termination period configured
**Type:** Read-only | **Duration:** 1 min

**Objective:** Stateless pods have `terminationGracePeriodSeconds=35`.

**Steps:**
1. `kubectl get pod <pod> -n robot-shop -o jsonpath='{.spec.terminationGracePeriodSeconds}'`
2. Verify value is 35

**Expected Results:**
- [ ] All stateless services have terminationGracePeriodSeconds=35

---

### EVICT-003: PreStop hook configured
**Type:** Read-only | **Duration:** 1 min

**Objective:** Stateless pod containers have a preStop lifecycle hook.

**Steps:**
1. `kubectl get pod <pod> -n robot-shop -o jsonpath='{.spec.containers[0].lifecycle.preStop}'`
2. Verify preStop hook exists

**Expected Results:**
- [ ] All stateless service containers have a preStop hook

---

### EVICT-004: Multi-node drain from different pools
**Type:** Destructive | **Duration:** 3 min

**Objective:** Draining 2 nodes from different spot pools, all services recover.

**Steps:**
1. Pick 1 node from each of 2 different spot pools
2. Drain both nodes
3. Wait for pods to reschedule
4. Verify all 12 services have running pods

**Expected Results:**
- [ ] All services have >= 1 running pod after drain

**Rollback:** `kubectl uncordon` both nodes

---

### EVICT-005: PDB respected during drain
**Type:** Destructive | **Duration:** 3 min

**Objective:** Running replica count never drops below PDB minAvailable=1 during drain.

**Steps:**
1. Record running counts for PDB services
2. Drain a spot node
3. Poll every 5s during drain
4. Record minimum running count observed

**Expected Results:**
- [ ] Every PDB service maintains >= 1 running pod throughout

**Rollback:** `kubectl uncordon <node>`

---

### EVICT-006: Service endpoint removal on drain
**Type:** Destructive | **Duration:** 2 min

**Objective:** Service endpoints are removed before pod termination.

**Steps:**
1. Record web service endpoint count: `kubectl get endpoints web -n robot-shop`
2. Drain node hosting a web pod
3. Verify endpoint count reduced

**Expected Results:**
- [ ] Endpoint count decreases during drain

**Rollback:** `kubectl uncordon <node>`

---

### EVICT-007: DaemonSet survival during drain
**Type:** Destructive | **Duration:** 2 min

**Objective:** DaemonSets are ignored during `--ignore-daemonsets` drain.

**Steps:**
1. Count DaemonSet pods on target node
2. Drain with `--ignore-daemonsets`
3. Verify only DaemonSet pods remain on node

**Expected Results:**
- [ ] Non-DaemonSet pods evicted
- [ ] DaemonSet pods remain

**Rollback:** `kubectl uncordon <node>`

---

### EVICT-008: Drain during deployment rollout
**Type:** Destructive | **Duration:** 4 min

**Objective:** Deployment rollout completes despite simultaneous node drain.

**Steps:**
1. `kubectl rollout restart deployment/web -n robot-shop`
2. Wait 3s, then drain a spot node
3. `kubectl rollout status deployment/web -n robot-shop --timeout=180s`
4. Verify web pods are running

**Expected Results:**
- [ ] Rollout completes successfully
- [ ] Web pods are Running

**Rollback:** `kubectl uncordon <node>`

---

### EVICT-009: Empty node drain - no disruption
**Type:** Destructive | **Duration:** 1 min

**Objective:** Draining a node with no/few user pods causes no disruption.

**Steps:**
1. Find spot node with fewest user pods
2. Cordon it, then drain
3. Verify total running pods unchanged

**Expected Results:**
- [ ] Drain completes quickly
- [ ] No service disruption

**Rollback:** `kubectl uncordon <node>`

---

### EVICT-010: Simultaneous 3-pool drain
**Type:** Destructive | **Duration:** 5 min

**Objective:** Draining 1 node from each of 3 spot pools simultaneously.

**Steps:**
1. Pick 1 node from 3 different spot pools
2. Drain all 3 simultaneously (background processes)
3. Wait for recovery
4. Verify all services running

**Expected Results:**
- [ ] All 12 services have running pods after 3-pool drain

**Rollback:** `kubectl uncordon` all 3 nodes

---

## Category 3: PDB Enforcement

### PDB-001: PDBs exist for protected services
**Type:** Read-only | **Duration:** 1 min

**Objective:** 7 PDBs exist for web, cart, catalogue, mongodb, mysql, redis, rabbitmq.

**Steps:**
1. `kubectl get pdb -n robot-shop`
2. Verify each protected service has a PDB

**Expected Results:**
- [ ] >= 7 PDBs exist
- [ ] Each PDB_SERVICE has a matching PDB

---

### PDB-002: All PDBs have minAvailable=1
**Type:** Read-only | **Duration:** 1 min

**Steps:**
1. `kubectl get pdb -n robot-shop -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.minAvailable}{"\n"}{end}'`
2. Verify all show `1`

**Expected Results:**
- [ ] All PDBs have minAvailable=1

---

### PDB-003: PDB status healthy
**Type:** Read-only | **Duration:** 1 min

**Objective:** All PDBs show disruptionsAllowed > 0.

**Steps:**
1. `kubectl get pdb -n robot-shop -o wide`
2. Check ALLOWED-DISRUPTIONS column

**Expected Results:**
- [ ] All PDBs have disruptionsAllowed > 0
- [ ] All PDBs have currentHealthy > 0

---

### PDB-004: PDB blocks eviction at minimum replicas
**Type:** Destructive | **Duration:** 3 min

**Objective:** PDB prevents pod eviction when at minAvailable.

**Steps:**
1. `kubectl scale deployment web -n robot-shop --replicas=1`
2. Wait for scale-down
3. Verify PDB disruptionsAllowed=0
4. Attempt eviction via `kubectl create -f eviction.yaml`
5. Verify eviction blocked

**Expected Results:**
- [ ] PDB disruptionsAllowed=0 at 1 replica
- [ ] Eviction attempt blocked

**Rollback:** `kubectl scale deployment web --replicas=<original>`

---

### PDB-005: PDB allows drain with headroom
**Type:** Destructive | **Duration:** 3 min

**Objective:** With replicas > minAvailable, drain succeeds.

**Steps:**
1. `kubectl scale deployment web -n robot-shop --replicas=3`
2. Drain node hosting 1 web pod
3. Verify >= 1 web pod remains running (PDB satisfied)

**Expected Results:**
- [ ] Drain completes without PDB violation
- [ ] web running count >= 1

**Rollback:** `kubectl uncordon <node>`, restore replica count

---

### PDB-006: PDB selector matches pods
**Type:** Read-only | **Duration:** 1 min

**Objective:** PDB label selectors match actual pod labels.

**Steps:**
1. Get each PDB's `.spec.selector.matchLabels`
2. `kubectl get pods -n robot-shop -l <selector>`
3. Verify at least 1 pod matches

**Expected Results:**
- [ ] Every PDB selector matches >= 1 pod

---

## Category 4: Topology Spread

### TOPO-001: Zone spread constraint present
**Type:** Read-only | **Duration:** 1 min

**Objective:** Stateless pods have TSC for `topology.kubernetes.io/zone`.

**Steps:**
1. Inspect pod spec for topologySpreadConstraints
2. Verify zone TSC exists

**Expected Results:**
- [ ] All stateless services have zone TSC

---

### TOPO-002: Zone maxSkew=1 and ScheduleAnyway
**Type:** Read-only | **Duration:** 1 min

**Steps:**
1. Get zone TSC from pod spec
2. Verify maxSkew=1
3. Verify whenUnsatisfiable=ScheduleAnyway

**Expected Results:**
- [ ] Zone maxSkew=1
- [ ] whenUnsatisfiable=ScheduleAnyway

---

### TOPO-003: Priority type spread (maxSkew=2)
**Type:** Read-only | **Duration:** 1 min

**Objective:** TSC on `kubernetes.azure.com/scalesetpriority` with maxSkew=2.

**Steps:**
1. Get priority type TSC from pod spec
2. Verify maxSkew=2, ScheduleAnyway

**Expected Results:**
- [ ] Priority TSC maxSkew=2

---

### TOPO-004: Hostname spread (maxSkew=1)
**Type:** Read-only | **Duration:** 1 min

**Objective:** TSC on `kubernetes.io/hostname` with maxSkew=1.

**Steps:**
1. Get hostname TSC from pod spec
2. Verify maxSkew=1, ScheduleAnyway

**Expected Results:**
- [ ] Hostname TSC maxSkew=1

---

### TOPO-005: Spread maintained after disruption
**Type:** Destructive | **Duration:** 3 min

**Objective:** Zone distribution approximately maintained after node drain.

**Steps:**
1. Record zone distribution for web and cart
2. Drain 1 spot node
3. Wait for recovery
4. Re-check zone distribution

**Expected Results:**
- [ ] Pods still in multiple zones after recovery

**Rollback:** `kubectl uncordon <node>`

---

## Category 5: Recovery & Rescheduling

### RECV-001: Pod reschedule time
**Type:** Destructive | **Duration:** 3 min

**Objective:** Pods reschedule within 120 seconds after drain.

**Steps:**
1. Record pods on target node
2. Drain node, start timer
3. Wait for all pods Running, stop timer

**Expected Results:**
- [ ] Reschedule time < 120 seconds

**Rollback:** `kubectl uncordon <node>`

---

### RECV-002: Service continuity during drain
**Type:** Destructive | **Duration:** 3 min

**Objective:** Running count never drops below minAvailable=1 during drain.

**Steps:**
1. Drain spot node in background
2. Poll PDB services every 3s for 60s
3. Record minimum running count per service

**Expected Results:**
- [ ] All PDB services maintain >= 1 running pod

**Rollback:** `kubectl uncordon <node>`

---

### RECV-003: Replacement pool selection
**Type:** Destructive | **Duration:** 3 min

**Objective:** Displaced pods prefer spot pools over standard.

**Steps:**
1. Record services on target spot node
2. Drain the node
3. Check where displaced pods landed
4. Calculate spot vs standard ratio

**Expected Results:**
- [ ] >= 50% of replacement pods on spot nodes

**Rollback:** `kubectl uncordon <node>`

---

### RECV-004: Node replacement provisioning
**Type:** Destructive | **Duration:** 5 min

**Objective:** Autoscaler provisions a replacement node after drain.

**Steps:**
1. Record node count in target spot pool
2. Drain a node from that pool
3. Wait up to 5 min for autoscaler to add a node
4. Verify pool node count restored

**Expected Results:**
- [ ] Pool node count returns to pre-drain level (or autoscaler deems pool right-sized)

**Rollback:** `kubectl uncordon <node>`

---

### RECV-005: Multi-service recovery
**Type:** Destructive | **Duration:** 3 min

**Objective:** All services on a shared node recover after drain.

**Steps:**
1. Find spot node with pods from >= 2 services
2. Drain the node
3. Verify all affected services have running pods

**Expected Results:**
- [ ] All displaced services recovered

**Rollback:** `kubectl uncordon <node>`

---

### RECV-006: Rapid sequential drains
**Type:** Destructive | **Duration:** 4 min

**Objective:** Full recovery after 2 drains 30 seconds apart.

**Steps:**
1. Drain spot node A
2. Wait 30 seconds
3. Drain spot node B
4. Wait for full recovery

**Expected Results:**
- [ ] All services have running pods after both drains

**Rollback:** `kubectl uncordon` both nodes

---

## Category 6: Sticky Fallback

### STICK-001: Fallback to standard pool
**Type:** Destructive | **Duration:** 3 min

**Objective:** Pods land on stdworkload when spot pool drained.

**Steps:**
1. Drain all nodes in one spot pool
2. Wait for pod rescheduling
3. Count pods on standard pool nodes

**Expected Results:**
- [ ] Pods scheduled on standard pool after spot drain

**Rollback:** `kubectl uncordon` all drained nodes

---

### STICK-002: Pods stay on standard (sticky behavior)
**Type:** Destructive | **Duration:** 3 min

**Objective:** Pods do NOT auto-migrate back to spot after capacity recovery.

**Steps:**
1. Drain a spot pool (pods fall to standard)
2. Wait 60 seconds
3. Uncordon spot nodes (simulating capacity recovery)
4. Wait 10 seconds
5. Verify pods still on standard

**Expected Results:**
- [ ] Pods remain on standard after spot recovery (sticky)

**Rollback:** `kubectl uncordon` all drained nodes

---

### STICK-003: Descheduler configured
**Type:** Read-only | **Duration:** 1 min

**Objective:** Descheduler exists with `RemovePodsViolatingNodeAffinity` strategy.

**Steps:**
1. `kubectl get deployment -n kube-system -l app=descheduler` (or similar)
2. Check ConfigMap for RemovePodsViolatingNodeAffinity

**Expected Results:**
- [ ] Descheduler deployment exists
- [ ] RemovePodsViolatingNodeAffinity strategy enabled

---

### STICK-004: Descheduler interval is 5m
**Type:** Read-only | **Duration:** 1 min

**Steps:**
1. Check descheduler ConfigMap or args for deschedulingInterval
2. Verify value is 5m or 300s

**Expected Results:**
- [ ] Descheduling interval = 5 minutes

---

### STICK-005: New pods prefer spot when available
**Type:** Destructive | **Duration:** 2 min

**Objective:** Newly created pods prefer spot nodes.

**Steps:**
1. Verify spot nodes available and schedulable
2. Scale web up by 2 replicas
3. Check where new pods landed
4. Restore original replica count

**Expected Results:**
- [ ] >= 50% of new pods on spot nodes

**Rollback:** Restore web replica count

---

## Category 7: VMSS & Node Pool (Read-Only via az CLI)

### VMSS-001: Spot pool VMSS configuration
**Type:** Read-only | **Duration:** 1 min

**Objective:** Verify priority=Spot, evictionPolicy=Delete, maxPrice=-1.

**Steps:**
1. `az vmss show -n <vmss> -g MC_<rg>_<cluster>_<loc>` for each spot pool
2. Check virtualMachineProfile.priority
3. Check virtualMachineProfile.evictionPolicy
4. Check virtualMachineProfile.billingProfile.maxPrice

**Expected Results:**
- [ ] All spot VMSS: priority=Spot
- [ ] All spot VMSS: evictionPolicy=Delete
- [ ] All spot VMSS: maxPrice=-1

---

### VMSS-002: Zone alignment matches config
**Type:** Read-only | **Duration:** 1 min

**Steps:**
1. `az vmss list -g MC_<rg>` and check zones per pool
2. spotgeneral1 → zone 1, spotmemory1 → zone 2, spotgeneral2 → zone 2, spotcompute → zone 3, spotmemory2 → zone 3

**Expected Results:**
- [ ] Each VMSS zone matches configuration

---

### VMSS-003: VM SKU matches pool config
**Type:** Read-only | **Duration:** 1 min

**Steps:**
1. `az vmss list -g MC_<rg>` and check sku.name per pool

**Expected Results:**
- [ ] spotgeneral1: Standard_D4s_v5
- [ ] spotmemory1: Standard_E4s_v5
- [ ] spotgeneral2: Standard_D8s_v5
- [ ] spotcompute: Standard_F8s_v2
- [ ] spotmemory2: Standard_E8s_v5

---

### VMSS-004: Autoscale ranges match config
**Type:** Read-only | **Duration:** 1 min

**Steps:**
1. `az aks nodepool list --cluster-name <cluster> -g <rg>`
2. Check minCount/maxCount and enableAutoScaling per pool

**Expected Results:**
- [ ] system: 3-6, autoscaling=true
- [ ] stdworkload: 2-10, autoscaling=true
- [ ] spotgeneral1: 0-20, autoscaling=true
- [ ] spotmemory1: 0-15, autoscaling=true
- [ ] spotgeneral2: 0-15, autoscaling=true
- [ ] spotcompute: 0-10, autoscaling=true
- [ ] spotmemory2: 0-10, autoscaling=true

---

### VMSS-005: Node labels match pool type
**Type:** Read-only | **Duration:** 1 min

**Steps:**
1. `kubectl get nodes -l agentpool=<pool> -o json` for each pool type
2. Check labels: workload-type, priority, kubernetes.azure.com/scalesetpriority

**Expected Results:**
- [ ] Spot pools: workload-type=spot, priority=spot, scalesetpriority=spot
- [ ] Standard: workload-type=standard, priority=on-demand
- [ ] System: node-pool-type=system

---

### VMSS-006: Spot nodes have NoSchedule taint
**Type:** Read-only | **Duration:** 1 min

**Steps:**
1. `kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o json`
2. Check `.spec.taints` for `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`

**Expected Results:**
- [ ] All spot nodes have the NoSchedule taint

---

## Category 8: Autoscaler

### AUTO-001: Priority expander ConfigMap order
**Type:** Read-only | **Duration:** 1 min

**Objective:** ConfigMap has correct tier ordering 5/10/20/30.

**Steps:**
1. `kubectl get configmap cluster-autoscaler-priority-expander -n kube-system -o yaml`
2. Verify priority 5 contains memory pools (spotmemory1, spotmemory2)
3. Verify priority 10 contains general/compute pools
4. Verify priority 20 contains stdworkload
5. Verify priority 30 contains system

**Expected Results:**
- [ ] Tier 5 exists with memory spot pools
- [ ] Tier 10 exists with general/compute spot pools
- [ ] Tier 20 exists with standard pool
- [ ] Tier 30 exists with system pool

---

### AUTO-002: Autoscaler profile settings
**Type:** Read-only (az CLI) | **Duration:** 1 min

**Steps:**
1. `az aks show -n <cluster> -g <rg> --query autoScalerProfile`
2. Verify each setting matches variables.tf defaults

**Expected Results:**
- [ ] expander=priority
- [ ] scanInterval=20s
- [ ] maxGracefulTerminationSec=60
- [ ] scaleDownUnreadyTime=3m
- [ ] scaleDownUnneededTime=5m
- [ ] scaleDownDelayAfterDelete=10s
- [ ] maxNodeProvisionTime=10m
- [ ] skipNodesWithSystemPods=true

---

### AUTO-003: Scale-up triggered by pending pods
**Type:** Destructive | **Duration:** 5 min

**Objective:** Creating pending pods triggers autoscaler scale-up.

**Steps:**
1. Deploy 3 pods with spot tolerations and moderate resource requests
2. Wait up to 5 min for autoscaler to provision nodes
3. Verify pods become Running
4. Delete test deployment

**Expected Results:**
- [ ] Pods scheduled and running within 5 minutes

**Rollback:** Delete test deployment

---

### AUTO-004: Scale-down configuration
**Type:** Read-only (az CLI) | **Duration:** 1 min

**Steps:**
1. `az aks show` and verify scale-down settings

**Expected Results:**
- [ ] scaleDownUtilizationThreshold=0.5
- [ ] scaleDownDelayAfterAdd=10m
- [ ] scaleDownDelayAfterFailure=3m
- [ ] skipNodesWithLocalStorage=false
- [ ] balanceSimilarNodeGroups=true

---

### AUTO-005: Balance similar node groups
**Type:** Read-only | **Duration:** 1 min

**Steps:**
1. `az aks show` query balanceSimilarNodeGroups
2. Check spot pool node counts are roughly balanced

**Expected Results:**
- [ ] balanceSimilarNodeGroups=true

---

## Category 9: Cross-Service Dependencies

### DEP-001: Frontend-backend connectivity after eviction
**Type:** Destructive | **Duration:** 3 min

**Objective:** web can reach catalogue after spot node drain.

**Steps:**
1. Drain spot node hosting web pods
2. Wait for web pods to reschedule
3. From web pod: test connectivity to catalogue service
4. `kubectl exec <web-pod> -- wget -q -O /dev/null -T 5 http://catalogue:8080/health`

**Expected Results:**
- [ ] Web pod can reach catalogue after drain

**Rollback:** `kubectl uncordon <node>`

---

### DEP-002: Database connectivity after node drain
**Type:** Destructive | **Duration:** 2 min

**Objective:** Database services (mongodb, mysql, redis) remain accessible.

**Steps:**
1. Drain a spot node
2. Verify database services have endpoints
3. Verify database pods are Running

**Expected Results:**
- [ ] mongodb, mysql, redis all have endpoints after drain
- [ ] All database pods Running

**Rollback:** `kubectl uncordon <node>`

---

### DEP-003: Queue service resilience
**Type:** Destructive | **Duration:** 2 min

**Objective:** RabbitMQ consumers (dispatch, shipping) recover after drain.

**Steps:**
1. Find spot node with dispatch or shipping pods
2. Drain the node
3. Verify rabbitmq, dispatch, shipping all running

**Expected Results:**
- [ ] RabbitMQ running
- [ ] Dispatch recovered
- [ ] Shipping recovered

**Rollback:** `kubectl uncordon <node>`

---

### DEP-004: Cart persistence across eviction
**Type:** Destructive | **Duration:** 2 min

**Objective:** Cart service reconnects to Redis after spot eviction.

**Steps:**
1. Verify redis running (on standard, not spot)
2. Drain spot node hosting cart pods
3. Verify cart recovered and can reach redis

**Expected Results:**
- [ ] Cart pod recovered after drain
- [ ] Redis still running (not on spot)
- [ ] Cart can resolve redis service

**Rollback:** `kubectl uncordon <node>`

---

### DEP-005: Full service mesh health
**Type:** Destructive | **Duration:** 3 min

**Objective:** All 12 services running with endpoints after drain and recovery.

**Steps:**
1. Drain a spot node
2. Wait for recovery
3. Check all 12 services for running pods
4. Check all 12 services for endpoints

**Expected Results:**
- [ ] All 12 services have running pods
- [ ] All 12 services have endpoints

**Rollback:** `kubectl uncordon <node>`

---

## Category 10: Edge Cases

### EDGE-001: All spot nodes cordoned
**Type:** Destructive | **Duration:** 5 min

**Objective:** 100% fallback to standard when all spot cordoned/drained.

**Steps:**
1. Cordon all spot nodes
2. Drain all spot nodes
3. Verify standard pool absorbs workload
4. Verify all services running

**Expected Results:**
- [ ] Standard pool has nodes
- [ ] All services running on standard/system

**Rollback:** `kubectl uncordon` all spot nodes

---

### EDGE-002: Rapid cordon/uncordon cycling
**Type:** Destructive | **Duration:** 2 min

**Objective:** Cluster stays stable after 3 rapid cordon/uncordon cycles.

**Steps:**
1. Pick a spot node
2. Cordon, wait 3s, uncordon, wait 3s (repeat 3x)
3. Verify node schedulable
4. Verify pod count stable

**Expected Results:**
- [ ] Node schedulable after cycling
- [ ] Pod count unchanged

**Rollback:** `kubectl uncordon <node>`

---

### EDGE-003: Zero spot capacity with full fallback
**Type:** Destructive | **Duration:** 5 min

**Objective:** All services survive with zero spot capacity, then recover.

**Steps:**
1. Cordon and drain ALL spot nodes
2. Verify zero pods on spot
3. Verify all services running on standard
4. Uncordon all (recovery)

**Expected Results:**
- [ ] Zero pods on spot nodes
- [ ] All 12 services running during zero-spot

**Rollback:** `kubectl uncordon` all spot nodes

---

### EDGE-004: PDB + topology constraint interaction
**Type:** Destructive | **Duration:** 3 min

**Objective:** PDB respected even when topology constraints violated.

**Steps:**
1. Find a zone with 2+ spot nodes
2. Drain both (creates topology imbalance)
3. Verify PDB services >= minAvailable=1

**Expected Results:**
- [ ] All PDB services maintain >= 1 running pod despite topology imbalance

**Rollback:** `kubectl uncordon` all drained nodes

---

### EDGE-005: Standard pool resource pressure
**Type:** Destructive | **Duration:** 3 min

**Objective:** Pods go pending when standard pool is full, autoscaler scales up.

**Steps:**
1. Drain a spot node (pushes load to standard)
2. Check standard pool utilization
3. If pods pending, wait for autoscaler scale-up
4. Verify all services running

**Expected Results:**
- [ ] Standard pool absorbs workload or autoscaler scales up
- [ ] All services eventually running

**Rollback:** `kubectl uncordon <node>`

---

## Results Summary Template

| Category | Total | Pass | Fail | Skip | Notes |
|----------|-------|------|------|------|-------|
| 01 Pod Distribution | 10 | | | | |
| 02 Eviction Behavior | 10 | | | | |
| 03 PDB Enforcement | 6 | | | | |
| 04 Topology Spread | 5 | | | | |
| 05 Recovery & Rescheduling | 6 | | | | |
| 06 Sticky Fallback | 5 | | | | |
| 07 VMSS & Node Pool | 6 | | | | |
| 08 Autoscaler | 5 | | | | |
| 09 Cross-Service | 5 | | | | |
| 10 Edge Cases | 5 | | | | |
| **Total** | **63** | | | | |

## Known Issues & Workarounds

| Issue | Impact | Workaround | Reference |
|-------|--------|------------|-----------|
| Nodes not drained on spot eviction | Pods crash instead of graceful reschedule | PDBs + preStop hooks mitigate | GitHub #3528 |
| Delete policy becomes Stop | Nodes linger in NotReady | scale_down_unready=3m auto-cleans | GitHub #4400 |
| VMSS ghost instances | Blocked pool capacity | Node auto-repair + manual `az vmss delete-instances` | GitHub #4674 |
| Sticky fallback | Pods stay on standard after spot recovery | Deploy descheduler with 5m interval | SPOT_EVICTION_SCENARIOS.md |
