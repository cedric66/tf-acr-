###############################################################################
# AKS Spot-Optimized Module - Outputs
# Purpose: Export cluster and node pool information for downstream consumption
###############################################################################

###############################################################################
# Cluster Outputs
###############################################################################

output "cluster_id" {
  description = "The ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "The name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "kube_config" {
  description = "Raw Kubernetes config to be used by kubectl"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kube_config_host" {
  description = "The Kubernetes cluster server host"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive   = true
}

output "kube_admin_config" {
  description = "Raw Kubernetes admin config"
  value       = azurerm_kubernetes_cluster.main.kube_admin_config_raw
  sensitive   = true
}

output "cluster_identity" {
  description = "The identity of the AKS cluster"
  value = {
    type         = azurerm_kubernetes_cluster.main.identity[0].type
    principal_id = azurerm_kubernetes_cluster.main.identity[0].principal_id
    tenant_id    = azurerm_kubernetes_cluster.main.identity[0].tenant_id
  }
}

output "kubelet_identity" {
  description = "The kubelet identity for the AKS cluster"
  value = {
    client_id   = azurerm_kubernetes_cluster.main.kubelet_identity[0].client_id
    object_id   = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
    user_assigned_identity_id = azurerm_kubernetes_cluster.main.kubelet_identity[0].user_assigned_identity_id
  }
}

output "node_resource_group" {
  description = "The name of the resource group containing the AKS node resources"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

###############################################################################
# Node Pool Outputs
###############################################################################

output "system_node_pool" {
  description = "Information about the system node pool"
  value = {
    name     = azurerm_kubernetes_cluster.main.default_node_pool[0].name
    vm_size  = azurerm_kubernetes_cluster.main.default_node_pool[0].vm_size
    zones    = azurerm_kubernetes_cluster.main.default_node_pool[0].zones
    min_count = azurerm_kubernetes_cluster.main.default_node_pool[0].min_count
    max_count = azurerm_kubernetes_cluster.main.default_node_pool[0].max_count
  }
}

output "standard_node_pools" {
  description = "Information about the standard (on-demand) node pools"
  value = {
    for name, pool in azurerm_kubernetes_cluster_node_pool.standard : name => {
      id        = pool.id
      name      = pool.name
      vm_size   = pool.vm_size
      zones     = pool.zones
      min_count = pool.min_count
      max_count = pool.max_count
      priority  = "on-demand"
    }
  }
}

output "spot_node_pools" {
  description = "Information about the spot node pools"
  value = {
    for name, pool in azurerm_kubernetes_cluster_node_pool.spot : name => {
      id              = pool.id
      name            = pool.name
      vm_size         = pool.vm_size
      zones           = pool.zones
      min_count       = pool.min_count
      max_count       = pool.max_count
      priority        = "spot"
      spot_max_price  = pool.spot_max_price
      eviction_policy = pool.eviction_policy
    }
  }
}

output "all_node_pools_summary" {
  description = "Summary of all node pools for quick reference"
  value = {
    total_pools = 1 + length(var.standard_pool_configs) + length(var.spot_pool_configs)
    system_pools = 1
    standard_pools = length(var.standard_pool_configs)
    spot_pools = length(var.spot_pool_configs)
    spot_pool_vm_sizes = [for pool in var.spot_pool_configs : pool.vm_size]
  }
}

###############################################################################
# Kubernetes Manifests Outputs
###############################################################################

output "priority_expander_configmap" {
  description = "ConfigMap YAML for cluster autoscaler priority expander"
  value = templatefile("${path.module}/templates/priority-expander.yaml.tpl", {
    spot_pools     = var.spot_pool_configs
    standard_pools = var.standard_pool_configs
  })
}

output "spot_tolerant_deployment_template" {
  description = "Template for deploying spot-tolerant workloads"
  value       = file("${path.module}/templates/spot-tolerant-deployment.yaml.tpl")
}

###############################################################################
# Cost Optimization Metrics
###############################################################################

output "estimated_cost_savings" {
  description = "Estimated cost savings configuration"
  value = {
    spot_discount_percentage = "60-90%"
    recommended_spot_ratio   = "60-80%"
    fallback_capacity_ratio  = "20-40%"
    note = "Actual savings depend on spot availability and eviction rates"
  }
}
