# AKS Spot Orchestration Prototypes

This directory contains Terraform prototypes for the two primary strategies identified in the research phase.

## 1. Native AKS Spot Pool (`spot_native_aks.tf`)
This is the standard, stable approach.
*   **Mechanism**: Uses `azurerm_kubernetes_cluster_node_pool` with `priority = "Spot"`.
*   **Pros**: Fully managed via Terraform API, stable, predictable.
*   **Cons**: Rigid VM Size (if `Standard_DS2_v2` is out of stock, it fails to scale).

## 2. Karpenter / Node Auto-Provisioning (`spot_karpenter_aks.tf`)
This uses the new "Node Autoprovisioning" (NAP) feature in AKS, which is a managed version of Karpenter.
*   **Mechanism**: `node_provisioning_mode = "Auto"` in the cluster config. Actual Spot configuration happens inside Kubernetes Manifests (CRDs), not Terraform arguments.
*   **Pros**: **Flexible SKUs**. If one instance type is unavailable, it automatically tries another family (e.g., D-series -> E-series).
*   **Cons**: Preview feature; requires specific network stack (Azure CNI Overlay + Cilium).

## How to use
1.  **For Native**: `terraform apply` the `spot_native_aks.tf` file.
2.  **For Karpenter**: 
    *   `terraform apply` the `spot_karpenter_aks.tf` file.
    *   Apply the commented-out YAML manifest (`kubectl apply -f nodepool.yaml`) to actually define the Spot logic.
