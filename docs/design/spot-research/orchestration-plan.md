# Spot Node Orchestration Research & Plan

## Objective
Design a strategy to orchestrate Spot Nodes in an AKS cluster, aiming for cost optimization (Spot instances) while maintaining reliability. The user specifically inquired about the roles of **KEDA** and **Karpenter** versus the **Native AKS** approach.

## Summary of Findings

| Feature | **Native AKS (VMSS)** | **KEDA** | **Karpenter (NAP)** |
| :--- | :--- | :--- | :--- |
| **Primary Role** | Node Orchestrator (via VMSS) | Workload Autoscaler (HPA extended) | Node Orchestrator (Direct Provider) |
| **Spot Support** | Supported (via VMSS Spot pools) | N/A (Does not manage nodes) | Excellent (Dynamic Spot SKU selection) |
| **Scaling Logic** | Reactive (Pending pods -> scale up) | Event-Driven (Metrics -> Pending pods) | Proactive/Real-time (Pending pods -> bind) |
| **Best For** | Standard production workloads | Event-driven apps (queues, streams) | High-churn, diverse instance needs |
| **Complexity** | Low (Built-in) | Medium (Add-on) | High (New provider, preview features) |

---

## Detailed Options Analysis

### Option A: Native AKS (VMSS + Cluster Autoscaler)
**Current Standard.** AKS manages Spot nodes using Virtual Machine Scale Sets (VMSS) in "Spot" mode.
*   **Mechanism**: You define a `nodepool` with `priority=Spot`. The Cluster Autoscaler listens for pending pods and scales this nodepool `0 -> N`.
*   **Scheduling**:
    *   Use **Taints/Tolerations** (`kubernetes.azure.com/scalesetpriority=spot:NoSchedule`) to prevent critical system pods from landing here.
    *   Use **Pod Topology Spread Constraints** (`topologyKey: topology.kubernetes.io/zone` + `whenUnsatisfiable: ScheduleAnyway`) to spread replicas across zones/nodes to minimize eviction impact.
*   **Pros**:
    *   Fully supported, stable, zero extra operational overhead.
    *   Integrated with Azure pricing/eviction handling (via Node Problem Detector / ecosystem).
*   **Cons**:
    *   **Rigid SKUs**: A node pool is tied to a specific VM size (e.g., `Standard_D2s_v3`). If that SKU is out of stock in Spot, you can't easily fall back to `Standard_D4s_v3` without creating a whole new node pool.
    *   **Slower**: VMSS scaling can be slower than direct pod binding.
    *   **Single VM**: "Single VM" pools don't exist in AKS; everything is a VMSS, even size 1.

### Option B: KEDA (Kubernetes Event-driven Autoscaling)
**Partner Implementation.** KEDA is **not** a node orchestrator.
*   **Mechanism**: KEDA scales *Deployments/Jobs* from 0 to 1+ based on external events (e.g., Service Bus queue length).
*   **Role in Spot**: KEDA creates the *demand* (pods). When KEDA scales a deployment to 50 replicas, it creates pending pods. The **Cluster Autoscaler** (or Karpenter) sees these pending pods and creates the Spot nodes.
*   **Verdict**: KEDA is a **trigger**, not a **manager** of nodes. It works perfectly *with* Option A or Option C but replaces neither.

### Option C: Karpenter (Node Auto-Provisioning - NAP)
**Advanced/Future Standard.** Karpenter bypasses VMSS constraints and creates VMs directly.
*   **Mechanism**: Karpenter observes pending pods and calls the Azure API to provision standard Azure VMs (not VMSS, or ephemeral VMSS) that *exactly* match the pod requirements.
*   **Role in Spot**:
    *   **Flexible SKUs**: You can define a `NodePool` allowing a list of instance types (e.g., `["Standard_D2*", "Standard_D4*"]`). Karpenter will pick the cheapest available Spot instance that fits the pod.
    *   **Consolidation**: Actively moves pods to cheaper nodes or consolidates them to empty nodes to save cost.
    *   **Fast**: Bypasses some VMSS overhead (though AKS integration still has some latency).
*   **Pros**:
    *   **Immense Flexibility**: Solves the "Spot SKU stockout" problem by falling back to other allowed instance types automatically.
    *   **Cost**: Tighter bin-packing.
*   **Cons**:
    *   **Maturity**: AKS implementation (NAP) is newer than AWS Karpenter.
    *   **Complexity**: Requires installing/managing the Karpenter controller (or enabling the NAP add-on).

---

## Implementation Plan

### 1. Decision Matrix
*   **Use Option A (Native)** if: You want stability, simple Terraform management, and accept that if a specific VM SKU is out of stock, that node pool won't scale.
*   **Use Option C (Karpenter)** if: You need aggressive cost savings, have workloads that are flexible on instance type, and need to survive "Spot Stockouts" by automatically falling back to other instance sizes.

### 2. Proposed Architecture (Hybrid - Best of Both)
We recommend a hybrid approach where **KEDA** handles application scaling (if event-driven) and the **Native AKS Autoscaler** (or Karpenter if agreed) handles the infrastructure.

#### Scenario 1: Native (Recommended for Simplicity)
*   **Terraform**: Create secondary `azurerm_kubernetes_cluster_node_pool` with `priority = "Spot"`.
*   **Code**: Add `tolerations` to deployment manifests.
*   **Availability**: Implement `topologySpreadConstraints` to ensure high availability across the spot nodes.

#### Scenario 2: Karpenter (Recommended for Flexibility)
*   **Terraform**: Enable AKS Node Autoprovisioning (NAP) or install Karpenter Helm chart.
*   **Config**: Create a Karpenter `NodePool` CRD that allows `spot` capacity type and a list of `requirements` (e.g., `family: [D, E]`, `cpu: [2, 4]`).
*   **Constraint**: Ensure AKS cluster identity has permission to create VMs.

## Next Steps
1.  **Select Strategy**: (User to confirm: Native vs Karpenter).
2.  **Prototype**: Create the Terraform for the selected strategy.
3.  **Validate**: Run a load test (using KEDA (optional) or manual replica scaling) to trigger Spot creation.
