###############################################################################
# Production Environment - AKS Spot-Optimized Configuration
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.80.0"
    }
  }

  # Local backend for development/testing
  backend "local" {}
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = "00000000-0000-0000-0000-000000000000" # Update with your subscription ID
}

###############################################################################
# Local Variables
###############################################################################

locals {
  environment = "prod"
  location    = "australiaeast"

  # Workspace-required tags
  tags = {
    environment = local.environment
    location    = local.location
    managed_by  = "terraform"
    project     = "aks-spot-optimization"
  }
}

###############################################################################
# Data Sources - Existing Resources
###############################################################################

# Use existing resource group
data "azurerm_resource_group" "main" {
  name = "rg-xxxxxx" # Update with your existing resource group name
}

# Use existing virtual network
data "azurerm_virtual_network" "main" {
  name                = "vnet-xxxxxx" # Update with your existing VNet name
  resource_group_name = "rg-xxxxxx"   # Update with VNet's resource group
}

# Use existing subnet
data "azurerm_subnet" "aks" {
  name                 = "snet-xxxxxx" # Update with your existing subnet name
  virtual_network_name = data.azurerm_virtual_network.main.name
  resource_group_name  = "rg-xxxxxx" # Update with VNet's resource group
}

###############################################################################
# Log Analytics Workspace (for monitoring)
###############################################################################

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-aks-${local.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

###############################################################################
# AKS Cluster with Spot Optimization
###############################################################################

module "aks" {
  source = "../../modules/aks-spot-optimized"

  cluster_name        = "aks-spot-${local.environment}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  kubernetes_version  = "1.34"
  vnet_subnet_id      = data.azurerm_subnet.aks.id
  tags                = local.tags

  # System pool - minimal, always-on for cluster components
  system_pool_config = {
    name                = "system"
    vm_size             = "Standard_D4s_v5"
    min_count           = 3
    max_count           = 5
    zones               = ["1", "2", "3"]
    os_disk_size_gb     = 128
    enable_auto_scaling = true
  }

  # Standard pools - fallback for spot evictions
  standard_pool_configs = [
    {
      name                = "stdworkload"
      vm_size             = "Standard_D4s_v5"
      min_count           = 2
      max_count           = 15
      zones               = ["1", "2"]
      os_disk_size_gb     = 128
      enable_auto_scaling = true
      labels = {
        "workload-tier" = "production"
      }
    }
  ]

  # Spot pools - diversified VM sizes for cost optimization
  spot_pool_configs = [
    # Spot Pool 1: General purpose, Zone 1
    {
      name            = "spotgen1"
      vm_size         = "Standard_D4s_v5"
      min_count       = 0
      max_count       = 25
      zones           = ["1"]
      spot_max_price  = -1 # Up to on-demand price
      eviction_policy = "Delete"
      priority_weight = 10
      labels = {
        "spot-pool-id" = "1"
        "vm-family"    = "general"
      }
    },
    # Spot Pool 2: General purpose (larger), Zone 2
    {
      name            = "spotgen2"
      vm_size         = "Standard_D8s_v5"
      min_count       = 0
      max_count       = 15
      zones           = ["2"]
      spot_max_price  = -1
      eviction_policy = "Delete"
      priority_weight = 10
      labels = {
        "spot-pool-id" = "2"
        "vm-family"    = "general"
      }
    },
    # Spot Pool 3: Compute optimized, Zone 3
    {
      name            = "spotcomp"
      vm_size         = "Standard_F8s_v2"
      min_count       = 0
      max_count       = 10
      zones           = ["3"]
      spot_max_price  = -1
      eviction_policy = "Delete"
      priority_weight = 10
      labels = {
        "spot-pool-id" = "3"
        "vm-family"    = "compute"
      }
    }
  ]

  # Autoscaler optimized for spot handling
  autoscaler_profile = {
    expander                         = "priority"
    balance_similar_node_groups      = true
    max_graceful_termination_sec     = 60
    max_node_provisioning_time       = "15m"
    new_pod_scale_up_delay           = "0s"
    scale_down_delay_after_add       = "10m"
    scale_down_delay_after_delete    = "10s"
    scale_down_unneeded              = "10m"
    scale_down_utilization_threshold = 0.5
    scan_interval                    = "10s"
  }

  # Monitoring
  enable_azure_monitor       = true
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # AAD Integration
  azure_ad_enabled = true
  enable_rbac      = true
  # admin_group_object_ids = ["<your-aad-group-id>"]
}

###############################################################################
# Outputs
###############################################################################

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = module.aks.cluster_id
}

output "node_pools_summary" {
  description = "Summary of all node pools"
  value       = module.aks.all_node_pools_summary
}

output "kube_config_command" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${data.azurerm_resource_group.main.name} --name ${module.aks.cluster_name}"
}

output "priority_expander_manifest" {
  description = "Priority expander ConfigMap for kubectl apply"
  value       = module.aks.priority_expander_configmap
}
