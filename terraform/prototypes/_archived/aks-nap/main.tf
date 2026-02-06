terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

# =============================================================================
# AKS Node Auto-Provisioning (NAP) / Karpenter
# =============================================================================
# STATUS: ✅ Generally Available (since July 2025)
#
# This prototype uses the `node_provisioning_mode` attribute which requires
# azurerm provider 4.x+ (post-July 2025 releases).
#
# If you encounter "unsupported argument" errors, enable NAP via Azure CLI:
#   az aks update -g <resource-group> -n <cluster-name> --node-provisioning-mode Auto
#
# REQUIREMENTS:
#   - Azure CNI Overlay + Cilium (network_plugin_mode = "overlay", network_dataplane = "cilium")
#   - System-assigned or User-assigned Managed Identity (no Service Principal)
#   - Linux nodes only
#
# INCOMPATIBLE:
#   - Kubenet
#   - Calico
#   - Windows nodes
#   - IPv6
# =============================================================================

provider "azurerm" {
  features {}
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-aks-nap-prototype"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "westeurope"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-nap-prototype"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = "Prototype"
    Purpose     = "Karpenter NAP Testing"
  }
}

# -----------------------------------------------------------------------------
# AKS Cluster with Node Autoprovisioning (Karpenter)
# -----------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "nap" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  # CRITICAL: Enable Node Autoprovisioning (Karpenter)
  # This replaces traditional node pools with dynamic provisioning
  node_provisioning_mode = "Auto"

  # REQUIRED for NAP: Azure CNI Overlay with Cilium
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
  }

  # System node pool (always on-demand for stability)
  default_node_pool {
    name                = "system"
    node_count          = 2
    vm_size             = "Standard_D4s_v5"
    os_disk_size_gb     = 128
    zones               = ["1", "2", "3"]
    only_critical_addons_enabled = true

    node_labels = {
      "kubernetes.azure.com/mode" = "system"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Auto-upgrade for security patches
  automatic_upgrade_channel = "patch"

  # Workload identity for secure Azure API access
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = {
    Environment = "Prototype"
    NodeProvisioning = "Karpenter-NAP"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  value = azurerm_kubernetes_cluster.nap.name
}

output "kube_config_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.nap.name}"
}

output "nap_enabled" {
  value = "Node Autoprovisioning (Karpenter) is enabled. Configure NodePool CRDs via kubectl."
}
