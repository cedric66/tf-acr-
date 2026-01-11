###############################################################################
# AKS Spot-Optimized Module - Main Configuration
# Purpose: Create AKS cluster with cost-optimized spot node pool strategy
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.80.0"
    }
  }
}

###############################################################################
# Locals
###############################################################################

locals {
  # Common labels applied to all node pools
  common_labels = merge(var.tags, {
    "managed-by" = "terraform"
    "cost-optimization" = "spot-enabled"
  })

  # System pool labels
  system_pool_labels = merge(local.common_labels, var.system_pool_config.labels, {
    "node-pool-type" = "system"
  })

  # Standard pool labels
  standard_pool_labels = {
    for pool in var.standard_pool_configs : pool.name => merge(local.common_labels, pool.labels, {
      "node-pool-type" = "user"
      "workload-type"  = "standard"
      "priority"       = "on-demand"
    })
  }

  # Spot pool labels
  spot_pool_labels = {
    for pool in var.spot_pool_configs : pool.name => merge(local.common_labels, pool.labels, {
      "node-pool-type" = "user"
      "workload-type"  = "spot"
      "priority"       = "spot"
    })
  }
}

###############################################################################
# AKS Cluster
###############################################################################

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  tags = var.tags

  # System Node Pool (Default Pool)
  default_node_pool {
    name                         = var.system_pool_config.name
    vm_size                      = var.system_pool_config.vm_size
    node_count                   = var.system_pool_config.enable_auto_scaling ? null : var.system_pool_config.node_count
    min_count                    = var.system_pool_config.enable_auto_scaling ? var.system_pool_config.min_count : null
    max_count                    = var.system_pool_config.enable_auto_scaling ? var.system_pool_config.max_count : null
    zones                        = var.system_pool_config.zones
    os_disk_size_gb              = var.system_pool_config.os_disk_size_gb
    os_disk_type                 = var.system_pool_config.os_disk_type
    max_pods                     = var.system_pool_config.max_pods
    enable_auto_scaling          = var.system_pool_config.enable_auto_scaling
    vnet_subnet_id               = var.vnet_subnet_id
    only_critical_addons_enabled = true  # System pool - only kube-system pods
    node_labels                  = local.system_pool_labels

    upgrade_settings {
      max_surge = "25%"
    }
  }

  # Identity
  identity {
    type = var.identity_type
  }

  # Network Profile
  network_profile {
    network_plugin    = var.network_profile.network_plugin
    network_policy    = var.network_profile.network_policy
    dns_service_ip    = var.network_profile.dns_service_ip
    service_cidr      = var.network_profile.service_cidr
    load_balancer_sku = var.network_profile.load_balancer_sku
    outbound_type     = var.network_profile.outbound_type
  }

  # Cluster Autoscaler Profile - Optimized for Spot
  auto_scaler_profile {
    balance_similar_node_groups      = var.autoscaler_profile.balance_similar_node_groups
    expander                         = var.autoscaler_profile.expander
    max_graceful_termination_sec     = var.autoscaler_profile.max_graceful_termination_sec
    max_node_provisioning_time       = var.autoscaler_profile.max_node_provisioning_time
    max_unready_nodes                = var.autoscaler_profile.max_unready_nodes
    max_unready_percentage           = var.autoscaler_profile.max_unready_percentage
    new_pod_scale_up_delay           = var.autoscaler_profile.new_pod_scale_up_delay
    scale_down_delay_after_add       = var.autoscaler_profile.scale_down_delay_after_add
    scale_down_delay_after_delete    = var.autoscaler_profile.scale_down_delay_after_delete
    scale_down_delay_after_failure   = var.autoscaler_profile.scale_down_delay_after_failure
    scale_down_unneeded              = var.autoscaler_profile.scale_down_unneeded
    scale_down_unready               = var.autoscaler_profile.scale_down_unready
    scale_down_utilization_threshold = var.autoscaler_profile.scale_down_utilization_threshold
    scan_interval                    = var.autoscaler_profile.scan_interval
    skip_nodes_with_local_storage    = var.autoscaler_profile.skip_nodes_with_local_storage
    skip_nodes_with_system_pods      = var.autoscaler_profile.skip_nodes_with_system_pods
  }

  # Azure Monitor (OMS Agent)
  dynamic "oms_agent" {
    for_each = var.enable_azure_monitor && var.log_analytics_workspace_id != null ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  # Azure AD RBAC
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.azure_ad_enabled ? [1] : []
    content {
      managed                = true
      azure_rbac_enabled     = var.enable_rbac
      admin_group_object_ids = var.admin_group_object_ids
    }
  }

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,  # Managed by autoscaler
      tags["LastUpdated"]
    ]
  }
}
