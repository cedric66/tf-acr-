# AKS Spot Node Migration Guide

**Target Audience:** Cloud Operations / SRE
**Purpose:** Concise execution guide to convert an existing AKS cluster to use Spot Node Pools.

---

## 1. Overview

This guide details the infrastructure changes required to migrate from a **Standard** AKS cluster to a **Spot-Optimized** cluster.

| Feature | Current State | Future State |
|---------|---------------|--------------|
| **User Pools** | Standard (On-Demand) | **Spot (Diversified)** |
| **System Pool** | Standard (Dedicated) | **Standard (Dedicated)** (Unchanged) |
| **Scaling Strategy** | Random / Balanced | **Priority-Based** (Cheapest First) |
| **Workloads** | No specific tolerations | **Spot Tolerations Added** |

---

## 2. Prerequisites

Before proceeding, ensure the existing cluster meets these requirements:

- [ ] **Kubernetes Version:** >= 1.28
- [ ] **Network Plugin:** Azure CNI or Kubenet
- [ ] **Node Pools:** VMSS-backed (Virtual Machine Scale Sets)
- [ ] **Cluster Autoscaler:** Enabled
- [ ] **Quota:** Sufficient vCPU quota for new Spot pools (check "Spot" quota in Azure Portal)

---

## 3. Future State Architecture

The target architecture implements a **diversified spot strategy** to minimize eviction impact:

1.  **System Pool:** 1x Standard Pool (Critical system components only)
2.  **User Pools:** 5x Spot Pools (Diversified by VM Family & Zone)
    -   `spotgeneral1` (D-series, Zone 1)
    -   `spotmemory1` (E-series, Zone 2) - *Preferred*
    -   `spotgeneral2` (D-series, Zone 2)
    -   `spotcompute` (F-series, Zone 3)
    -   `spotmemory2` (E-series, Zone 3) - *Preferred*
3.  **Priority Expander:** Kubernetes ConfigMap to force Autoscaler to prefer Spot pools over Standard.

---

## 4. Migration Steps

### Step 1: Update Autoscaler Profile

Optimize the cluster autoscaler for rapid spot replacement.

**Command (Azure CLI):**
```bash
az aks update -g <RESOURCE_GROUP> -n <CLUSTER_NAME> \
  --cluster-autoscaler-profile \
    expander=priority \
    scan-interval=20s \
    scale-down-unready=3m \
    scale-down-unneeded=5m \
    max-node-provisioning-time=10m
```

### Step 2: Deploy Infrastructure (Add Spot Pools)

Add the 5 spot pools. Use Terraform (recommended) or CLI.

**Terraform Configuration:**
Update your `main.tf` to include the spot pools. If using the `aks-spot-optimized` module:

```hcl
module "aks_spot" {
  source = "./modules/aks-spot-optimized"
  
  # ... existing config ...

  spot_pool_configs = [
    { name = "spotgeneral1", vm_size = "Standard_D4s_v5", zones = ["1"], priority_weight = 10 },
    { name = "spotmemory1",  vm_size = "Standard_E4s_v5", zones = ["2"], priority_weight = 5  }, # Preferred
    { name = "spotgeneral2", vm_size = "Standard_D8s_v5", zones = ["2"], priority_weight = 10 },
    { name = "spotcompute",  vm_size = "Standard_F8s_v2", zones = ["3"], priority_weight = 10 },
    { name = "spotmemory2",  vm_size = "Standard_E8s_v5", zones = ["3"], priority_weight = 5  }  # Preferred
  ]
}
```

**Apply Changes:**
```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### Step 3: Configure Priority Expander

This ConfigMap instructs the autoscaler to prefer the spot pools (Priority 10) over the system pool (Priority 50+).

**Create file `priority-expander.yaml`:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-priority-expander
  namespace: kube-system
data:
  priorities: |
    # 10 = Highest priority (Lowest number) -> Autoscaler tries these FIRST
    10:
      - .*spotmemory.*
    20:
      - .*spotgeneral.*
      - .*spotcompute.*
    # 50+ = Fallback / System
    50:
      - .*system.*
```

**Apply:**
```bash
kubectl apply -f priority-expander.yaml
```

### Step 4: Workload Migration

Existing workloads **will not move** automatically. You must add tolerations to deployments to allow them to schedule on Spot nodes.

**Patch Deployment (Example):**

```bash
kubectl patch deployment <DEPLOYMENT_NAME> -n <NAMESPACE> --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/tolerations/-",
    "value": {
      "key": "kubernetes.azure.com/scalesetpriority",
      "operator": "Equal",
      "value": "spot",
      "effect": "NoSchedule"
    }
  }
]'
```

*Note: For production, update your Helm charts or manifests source.*

### Step 5: Verification

1.  **Check Nodes:** Ensure new spot pools exist (they may be size 0 initially).
    ```bash
    kubectl get nodes -l kubernetes.azure.com/scalesetpriority=spot
    ```
2.  **Check Pods:** Verify pods are running on spot nodes.
    ```bash
    kubectl get pods -o wide --field-selector spec.nodeName!=<SYSTEM_NODE_NAME>
    ```

### Step 6: Cleanup (Post-Migration)

Once workloads are running on Spot:
1.  Scale down old Standard User Pools to 0.
2.  Delete old Standard User Pools.

---

**Rollback:**
If issues arise, scale up the Standard pools and remove the Spot toleration from deployments.
