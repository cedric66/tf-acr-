###############################################################################
# AKS Spot-Optimized Module - Node Pools
# Purpose: Create standard and spot node pools with proper configuration
###############################################################################

###############################################################################
# Standard (On-Demand) Node Pools
# Purpose: Fallback pools for critical workloads and spot eviction absorption
###############################################################################

resource "azurerm_kubernetes_cluster_node_pool" "standard" {
  for_each = { for pool in var.standard_pool_configs : pool.name => pool }

  name                    = each.value.name
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.main.id
  vm_size                 = each.value.vm_size
  min_count               = each.value.enable_auto_scaling ? each.value.min_count : null
  max_count               = each.value.enable_auto_scaling ? each.value.max_count : null
  node_count              = each.value.enable_auto_scaling ? null : each.value.min_count
  zones                   = each.value.zones
  os_disk_size_gb         = each.value.os_disk_size_gb
  os_disk_type            = each.value.os_disk_type
  os_sku                  = var.os_sku
  max_pods                = each.value.max_pods
  auto_scaling_enabled    = each.value.enable_auto_scaling
  scale_down_mode         = "Delete" # Release all resources on scale-down
  host_encryption_enabled = var.host_encryption_enabled
  vnet_subnet_id          = var.vnet_subnet_id
  mode                    = "User"

  # Standard pools have no taints - they accept all workloads
  node_labels = local.standard_pool_labels[each.key]
  node_taints = each.value.taints

  upgrade_settings {
    max_surge = "25%"
  }

  tags = merge(var.tags, {
    "node-pool-type" = "standard"
    "priority"       = "on-demand"
  })

  lifecycle {
    ignore_changes = [
      node_count, # Managed by autoscaler
    ]
  }
}

###############################################################################
# Spot Node Pools
# Purpose: Cost-optimized pools with diversified VM sizes to reduce eviction risk
###############################################################################

resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  for_each = { for pool in var.spot_pool_configs : pool.name => pool }

  name                    = each.value.name
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.main.id
  vm_size                 = each.value.vm_size
  min_count               = each.value.enable_auto_scaling ? each.value.min_count : null
  max_count               = each.value.enable_auto_scaling ? each.value.max_count : null
  node_count              = each.value.enable_auto_scaling ? null : each.value.min_count
  zones                   = each.value.zones
  os_disk_size_gb         = each.value.os_disk_size_gb
  os_disk_type            = each.value.os_disk_type
  os_sku                  = var.os_sku
  max_pods                = each.value.max_pods
  auto_scaling_enabled    = each.value.enable_auto_scaling
  scale_down_mode         = "Delete" # Required for spot: releases all resources on eviction
  host_encryption_enabled = var.host_encryption_enabled
  vnet_subnet_id          = var.vnet_subnet_id
  mode                    = "User"

  # Spot-specific configuration
  priority        = "Spot"
  eviction_policy = each.value.eviction_policy
  spot_max_price  = each.value.spot_max_price

  # Spot pools have taints - only tolerating pods can schedule
  node_labels = local.spot_pool_labels[each.key]

  # Default spot taint + any additional custom taints
  node_taints = concat(
    ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"],
    each.value.taints
  )

  upgrade_settings {
    max_surge = "25%"
  }

  tags = merge(var.tags, {
    "node-pool-type"  = "spot"
    "priority"        = "spot"
    "vm-size"         = each.value.vm_size
    "priority-weight" = tostring(each.value.priority_weight)
  })

  lifecycle {
    ignore_changes = [
      node_count, # Managed by autoscaler
    ]
  }
}
