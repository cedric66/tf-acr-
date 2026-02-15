# AKS Spot-Optimized Cluster: Deployment Guide

This guide covers the end-to-end process for deploying an AKS cluster with cost-optimized spot node pools, from infrastructure provisioning through workload deployment and monitoring.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Architecture Overview](#2-architecture-overview)
3. [Infrastructure Deployment](#3-infrastructure-deployment)
4. [Priority Expander Setup](#4-priority-expander-setup)
5. [Workload Deployment](#5-workload-deployment)
6. [Verification & Validation](#6-verification--validation)
7. [Monitoring Setup](#7-monitoring-setup)
8. [Operational Considerations](#8-operational-considerations)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Prerequisites

### Tools Required

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.5.0 | Infrastructure provisioning |
| Azure CLI (`az`) | >= 2.50 | Azure authentication and management |
| `kubectl` | Matching cluster K8s version | Kubernetes resource management |
| `helm` (optional) | >= 3.x | For Descheduler and monitoring stack |

### Azure Requirements

- An active Azure subscription with sufficient quota for the target region
- VM quota for the following families (check with `az vm list-usage`):
  - `Standard_D4s_v5` (4 vCPU) - system pool + standard pool + spot pool
  - `Standard_D8s_v5` (8 vCPU) - spot pool
  - `Standard_E4s_v5` / `Standard_E8s_v5` (4/8 vCPU) - memory-optimized spot pools
  - `Standard_F8s_v2` (8 vCPU) - compute-optimized spot pool
- Contributor role on the target subscription (or a custom role with AKS + VNet + Log Analytics permissions)
- An Azure AD group for cluster admin access (recommended)

### Authentication

```bash
# Login to Azure
az login

# Set the target subscription
az account set --subscription "<subscription-id>"

# Verify
az account show --query "{name:name, id:id}" -o table
```

---

## 2. Architecture Overview

The deployment creates the following infrastructure:

```
Resource Group
├── Virtual Network (10.0.0.0/16)
│   └── AKS Subnet (10.0.0.0/22 - 1024 IPs)
├── Log Analytics Workspace
└── AKS Cluster
    ├── System Pool       (3 nodes, D4s_v5, zones 1-2-3, on-demand)
    ├── Standard Pool     (2-15 nodes, D4s_v5, zones 1-2, on-demand)
    └── Spot Pools (5 pools)
        ├── spotmemory1   (0-15 nodes, E4s_v5, zone 2, priority 5)
        ├── spotmemory2   (0-10 nodes, E8s_v5, zone 3, priority 5)
        ├── spotgeneral1  (0-20 nodes, D4s_v5, zone 1, priority 10)
        ├── spotgeneral2  (0-15 nodes, D8s_v5, zone 2, priority 10)
        └── spotcompute   (0-10 nodes, F8s_v2, zone 3, priority 10)
```

**Priority Expander Tiers** (lower number = tried first):

| Priority | Pool Type | Purpose |
|----------|-----------|---------|
| 5 | Memory-optimized spot (E-series) | Lowest eviction risk, preferred |
| 10 | General/compute spot (D/F-series) | Standard spot capacity |
| 20 | Standard on-demand | Fallback when no spot available |
| 30 | System pool | Never used for user workloads |

---

## 3. Infrastructure Deployment

### Step 1: Configure Terraform Backend

Edit `terraform/environments/prod/main.tf` and uncomment the backend block:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "sttfstate<unique>"
    container_name       = "tfstate"
    key                  = "aks-prod.tfstate"
  }
}
```

If you don't have a remote backend, create one:

```bash
# Create storage account for Terraform state
az group create -n rg-terraform-state -l australiaeast
az storage account create -n sttfstate<unique> -g rg-terraform-state -l australiaeast --sku Standard_LRS
az storage container create -n tfstate --account-name sttfstate<unique>
```

### Step 2: Review and Customize Configuration

The production environment configuration is in `terraform/environments/prod/main.tf`. Key settings to review:

**Location and naming:**
```hcl
locals {
  environment = "prod"
  location    = "australiaeast"  # Change to your target region
}
```

**Spot pool configuration** - customize VM sizes, zones, and pool counts based on regional spot availability. Check current spot pricing and eviction rates:

```bash
# Check spot pricing in your target region
az vm list-skus --location australiaeast --size Standard_D --output table
az vm list-skus --location australiaeast --size Standard_E --output table
```

**Autoscaler profile** - the module defaults are tuned for spot workloads:

| Setting | Module Default | Purpose |
|---------|---------------|---------|
| `expander` | `priority` | Use Priority Expander for cost-optimized pool selection |
| `scan_interval` | `20s` | Microsoft-recommended for bursty workloads |
| `scale_down_unready` | `3m` | Remove ghost NotReady nodes from spot evictions quickly |
| `max_node_provisioning_time` | `10m` | Fail fast on stuck VMSS instances |
| `max_graceful_termination_sec` | `60` | Allow pods to drain gracefully during scale-down |
| `scale_down_unneeded` | `5m` | Faster scale-down for bursty workloads |

### Step 3: Initialize and Deploy

```bash
cd terraform/environments/prod

# Initialize Terraform (downloads providers, configures backend)
terraform init

# Validate configuration syntax
terraform validate

# Preview the deployment plan
terraform plan -out=tfplan

# Review the plan output carefully, then apply
terraform apply tfplan
```

Expected resources created:
- 1 Resource Group
- 1 Virtual Network + 1 Subnet
- 1 Log Analytics Workspace
- 1 AKS Cluster with 1 system pool
- 1 Standard node pool
- 5 Spot node pools (one per configuration entry)

### Step 4: Configure kubectl

After deployment completes:

```bash
# Get credentials (uses the output from Terraform)
az aks get-credentials \
  --resource-group rg-aks-prod \
  --name aks-prod

# Verify connectivity
kubectl get nodes -o wide
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot
```

---

## 4. Priority Expander Setup

The Cluster Autoscaler uses the `priority` expander to prefer spot pools over standard pools. This requires a ConfigMap in `kube-system`.

### Option A: Deploy via Terraform (recommended)

Set `deploy_priority_expander = true` in the module call. This requires the Kubernetes provider to be configured alongside AzureRM:

```hcl
module "aks" {
  source = "../../modules/aks-spot-optimized"
  # ... other settings ...
  deploy_priority_expander = true
}
```

### Option B: Deploy via kubectl

The module outputs the ConfigMap manifest. Apply it after cluster creation:

```bash
# Output the priority expander ConfigMap
terraform output -raw priority_expander_manifest > priority-expander.yaml

# Review the generated ConfigMap
cat priority-expander.yaml

# Apply to cluster
kubectl apply -f priority-expander.yaml
```

### Verify Priority Expander

```bash
# Confirm ConfigMap exists
kubectl get configmap cluster-autoscaler-priority-expander -n kube-system -o yaml

# Check autoscaler logs for priority expander loading
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50 | grep -i "priority"
```

Expected ConfigMap structure:

```yaml
data:
  priorities: |
    5:
      - .*spotmemory1.*
      - .*spotmemory2.*
    10:
      - .*spotgeneral1.*
      - .*spotgeneral2.*
      - .*spotcompute.*
    20:
      - .*stdworkload.*
    30:
      - .*system.*
```

**Important:** Without this ConfigMap, the autoscaler silently falls back to `random` expander, losing all cost-optimization ordering.

---

## 5. Workload Deployment

### Quick Start: Minimal Spot-Tolerant Deployment

For a basic workload that can run on spot nodes:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      tolerations:
        - key: kubernetes.azure.com/scalesetpriority
          operator: Equal
          value: spot
          effect: NoSchedule
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
      containers:
        - name: my-app
          image: my-app:latest
```

The two required elements are:
1. **Toleration** for `kubernetes.azure.com/scalesetpriority=spot:NoSchedule` - allows scheduling on spot nodes
2. **Node affinity preference** for `spot` - makes the scheduler prefer spot nodes but accept standard

### Production Deployment: Full Template

The module provides a complete spot-tolerant deployment template at `terraform/modules/aks-spot-optimized/templates/spot-tolerant-deployment.yaml.tpl`. It includes:

- **Pod Disruption Budget** (`minAvailable: 50%`)
- **Topology spread constraints** across zones, pool types, and nodes
- **Graceful shutdown** with preStop hook (25s drain + 35s termination grace)
- **Pod anti-affinity** to avoid co-locating replicas
- **Health checks** (liveness, readiness, startup probes)
- **Security context** (non-root, seccomp)

To use the template:

```bash
# Get the template
terraform output -raw spot_tolerant_deployment_template > my-app-deployment.yaml

# Replace placeholders
sed -i 's/${APP_NAME}/my-app/g' my-app-deployment.yaml
sed -i 's/${NAMESPACE}/production/g' my-app-deployment.yaml
sed -i 's|${IMAGE}|myregistry.azurecr.io/my-app:v1.0|g' my-app-deployment.yaml
sed -i 's/${REPLICAS}/6/g' my-app-deployment.yaml

# Review and apply
kubectl apply -f my-app-deployment.yaml
```

### Key Deployment Settings Explained

**Graceful shutdown sequence** (configured in the template):

```
T+0s:   Azure eviction notice (30s warning)
T+0s:   Pod marked NotReady, removed from Service endpoints
T+0s:   preStop hook fires: sends SIGTERM, sleeps 25s for drain
T+25s:  preStop completes
T+35s:  SIGKILL if container still running (terminationGracePeriodSeconds)
```

**Toleration for node disruptions** (in template):

```yaml
# Allow pods to remain on NotReady nodes for 30s during eviction
- key: node.kubernetes.io/not-ready
  operator: Exists
  effect: NoExecute
  tolerationSeconds: 30
```

This prevents immediate pod eviction when a node enters NotReady state, giving the system time to recover or gracefully drain.

---

## 6. Verification & Validation

### Verify Cluster Health

```bash
# All nodes should be Ready
kubectl get nodes -o wide

# Spot nodes should have the spot label and taint
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot -o wide
kubectl describe node <spot-node-name> | grep -A5 "Taints:"

# System pool should have critical-addons-only taint
kubectl describe node <system-node-name> | grep -A5 "Taints:"
```

### Verify Autoscaler

```bash
# Check autoscaler status
kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml

# Check for errors
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100 | grep -E "(error|warn)" -i
```

### Verify Pod Distribution

After deploying workloads:

```bash
# Check pod placement across nodes
kubectl get pods -o wide -n <namespace>

# Verify pods are on spot nodes
kubectl get pods -o wide -n <namespace> | while read line; do
  node=$(echo "$line" | awk '{print $7}')
  if [ "$node" != "NODE" ]; then
    priority=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/scalesetpriority}' 2>/dev/null)
    echo "$line -> $priority"
  fi
done

# Check topology distribution
kubectl get pods -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}'
```

### Run Test Workload

Deploy the included test workload to validate spot behavior:

```bash
kubectl apply -f tests/manifests/eviction-test-workload.yaml

# Watch pods distribute to spot nodes
kubectl get pods -o wide -w
```

---

## 7. Monitoring Setup

### Grafana Dashboards

Two pre-built Grafana dashboards are included in `monitoring/dashboards/`:

| Dashboard | File | Key Panels |
|-----------|------|------------|
| Spot Overview | `aks-spot-overview.json` | Eviction rate, pod distribution (spot vs on-demand), pending pods, active spot node count |
| Autoscaler Status | `aks-autoscaler-status.json` | Autoscaler health, scale-up/down events, unschedulable pods, per-pool node counts |

**Import to Grafana:**

1. Navigate to Grafana UI -> Dashboards -> Import
2. Upload the JSON files from `monitoring/dashboards/`
3. Configure the Prometheus data source when prompted

### Azure Monitor

The deployment includes Azure Monitor for containers via the Log Analytics workspace. Verify it is active:

```bash
# Check OMS agent pods
kubectl get pods -n kube-system -l component=oms-agent

# Check Log Analytics workspace is receiving data
az monitor log-analytics workspace show \
  --resource-group rg-aks-prod \
  --workspace-name log-aks-prod \
  --query "retentionInDays"
```

### Recommended Alerts

Set up alerts for the following conditions (see [SRE_OPERATIONAL_RUNBOOK.md](SRE_OPERATIONAL_RUNBOOK.md) for details):

| Alert | Severity | Condition |
|-------|----------|-----------|
| High eviction rate | P2 | >20 evictions/hour |
| All spot pools empty | P1 | 0 spot nodes for >5 minutes |
| Pods pending | P2 | >5 pods pending for >5 minutes |
| PDB violations | P1 | Any PDB violation |
| NotReady nodes | P2 | Any node NotReady for >5 minutes |

**Eviction Activity Log Alert** (Terraform example):

```hcl
resource "azurerm_monitor_activity_log_alert" "spot_eviction" {
  name                = "alert-spot-eviction"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = ["/subscriptions/${data.azurerm_subscription.current.subscription_id}"]

  criteria {
    operation_name = "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/preempt/action"
    category       = "Administrative"
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops_team.id
  }
}
```

---

## 8. Operational Considerations

### VMSS Ghost Instance Problem

After spot eviction, VMSS instances can get stuck in `Unknown`/`Failed` provisioning state instead of being deleted. This blocks the autoscaler from provisioning replacements in that pool.

**Automated mitigations (configured in module defaults):**

| Mechanism | Setting | Effect |
|-----------|---------|--------|
| `scale_down_unready` | `3m` | Autoscaler removes ghost NotReady nodes after 3 minutes |
| `max_node_provisioning_time` | `10m` | Autoscaler abandons stuck provisioning and retries |
| AKS Node Auto-Repair | Always on | Detects NotReady nodes after ~5 minutes, reimages or replaces |
| Priority Expander | Tiered fallback | Pending pods route to other spot pools or standard pool |

**Manual remediation** (if automated recovery fails):

```bash
# 1. Find the node resource group
NODE_RG=$(az aks show -g rg-aks-prod -n aks-prod --query nodeResourceGroup -o tsv)

# 2. List VMSS instances and find stuck ones
az vmss list-instances -g $NODE_RG -n <vmss-name> \
  --query "[].{name:name, state:provisioningState, zone:zones[0]}" -o table

# 3. Delete the ghost instance
az vmss delete-instances -g $NODE_RG -n <vmss-name> --instance-ids <instance-id>

# 4. Remove ghost node from Kubernetes
kubectl delete node <ghost-node-name>
```

See [SRE_OPERATIONAL_RUNBOOK.md](SRE_OPERATIONAL_RUNBOOK.md) Runbook 5 for the complete procedure.

### Sticky Fallback Problem

After spot eviction, pods land on standard on-demand nodes. When spot capacity recovers, pods **do not** automatically move back. This is by design in Kubernetes -- the scheduler is a one-shot operation.

**Solution: Kubernetes Descheduler**

Install the Descheduler with the `RemovePodsViolatingNodeAffinity` strategy:

```bash
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler/
helm install descheduler descheduler/descheduler \
  --namespace kube-system \
  --set schedule="*/5 * * * *" \
  --set deschedulerPolicy.strategies.RemovePodsViolatingNodeAffinity.enabled=true \
  --set deschedulerPolicy.strategies.RemovePodsViolatingNodeAffinity.params.nodeAffinityType[0]="preferredDuringSchedulingIgnoredDuringExecution"
```

This runs every 5 minutes, identifies pods on standard nodes that prefer spot, and evicts them so the scheduler places them back on cheaper spot capacity.

See [SPOT_EVICITION_SCENARIOS.md](SPOT_EVICITION_SCENARIOS.md) for detailed behavior and test instructions.

### Scaling Behavior

**Scale-up path** (pod pending -> node provisioned):

```
T+0s:   Pod created, no schedulable node
T+20s:  Autoscaler scan detects pending pod (scan_interval = 20s)
T+20s:  Priority Expander selects: memory spot (5) -> general spot (10) -> standard (20)
T+20s:  Scale-up request sent to selected pool's VMSS
T+2-4m: New node joins cluster, pod scheduled
```

**Scale-down path** (underutilized nodes removed):

```
T+0s:   Node utilization drops below 50% (scale_down_utilization_threshold)
T+5m:   Node marked unneeded for 5 minutes (scale_down_unneeded)
T+5m:   Pods drained with 60s graceful termination (max_graceful_termination_sec)
T+5m+:  Node removed from cluster
```

---

## 9. Troubleshooting

### Pods Stuck in Pending

```bash
# Check why pods are pending
kubectl describe pod <pod-name> -n <namespace>

# Check autoscaler status
kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml

# Check if priority expander ConfigMap exists
kubectl get configmap cluster-autoscaler-priority-expander -n kube-system

# Check autoscaler logs for scale-up failures
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=200 | grep -E "(scale.up|failed|error)" -i
```

Common causes:
- **Missing spot toleration** in pod spec - pods cannot schedule on tainted spot nodes
- **Missing priority expander ConfigMap** - autoscaler uses random expander, may not scale the right pool
- **Spot capacity unavailable** in region/zone - check Azure spot pricing dashboard
- **VM quota exceeded** - check `az vm list-usage --location <region>`

### Nodes Not Scaling Down

```bash
# Check which nodes the autoscaler considers for scale-down
kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml | grep -A20 "ScaleDown"

# Check for pods preventing scale-down
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=<node-name>
```

Common causes:
- Pods with local storage (`skip_nodes_with_local_storage = false` by default)
- System pods on user nodes (`skip_nodes_with_system_pods = true` by default)
- PDB preventing eviction
- Node utilization above threshold (50%)

### Spot Nodes Not Receiving Workloads

```bash
# Verify spot nodes have correct labels
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot --show-labels

# Verify spot nodes have the expected taint
kubectl describe node <spot-node> | grep -A5 "Taints"

# Verify pod has matching toleration
kubectl get pod <pod-name> -o yaml | grep -A10 "tolerations"
```

### VMSS Instance Stuck After Eviction

```bash
# Find the node resource group
NODE_RG=$(az aks show -g rg-aks-prod -n aks-prod --query nodeResourceGroup -o tsv)

# List all VMSS in the node resource group
az vmss list -g $NODE_RG --query "[].{name:name, capacity:sku.capacity}" -o table

# Check specific VMSS instances
az vmss list-instances -g $NODE_RG -n <vmss-name> \
  --query "[].{name:name, state:provisioningState, zone:zones[0]}" -o table

# Check Kubernetes node status
kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot | grep -E "NotReady|Unknown"
```

See [SRE_OPERATIONAL_RUNBOOK.md](SRE_OPERATIONAL_RUNBOOK.md) Runbook 5 for full ghost instance remediation steps.

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| [SPOT_EVICITION_SCENARIOS.md](SPOT_EVICITION_SCENARIOS.md) | Eviction scenarios, sticky fallback, VMSS ghost instances |
| [SRE_OPERATIONAL_RUNBOOK.md](SRE_OPERATIONAL_RUNBOOK.md) | Incident response runbooks (Runbooks 1-10) |
| [TROUBLESHOOTING_GUIDE.md](TROUBLESHOOTING_GUIDE.md) | Symptom-first diagnostic reference |
| [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) | Converting existing clusters to spot |
| [DEVOPS_TEAM_GUIDE.md](DEVOPS_TEAM_GUIDE.md) | Application team spot configuration |
| [AKS_SPOT_NODE_ARCHITECTURE.md](AKS_SPOT_NODE_ARCHITECTURE.md) | Core technical design |
| [CHAOS_ENGINEERING_TESTS.md](CHAOS_ENGINEERING_TESTS.md) | Resilience validation scenarios |
| [FINOPS_COST_ANALYSIS.md](FINOPS_COST_ANALYSIS.md) | Financial modeling and ROI |

---
**Last Updated**: 2026-02-05
**Status**: Production Ready
