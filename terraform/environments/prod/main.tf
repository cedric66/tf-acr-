###############################################################################
# Production Environment - AKS Spot-Optimized Configuration
###############################################################################

###############################################################################
# Local Variables
###############################################################################

locals {
  # Derive VNet resource group (defaults to main RG if not specified)
  # Derive VNet resource group (defaults to main RG if not specified)
  vnet_resource_group = coalesce(var.vnet_resource_group_name, var.resource_group_name)

  host_encryption_enabled = var.host_encryption_enabled
  tags                    = var.tags
}

###############################################################################
# Data Sources - Existing Resources
###############################################################################

# Use existing resource group
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Use existing virtual network
data "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  resource_group_name = local.vnet_resource_group
}

# Use existing subnet
data "azurerm_subnet" "aks" {
  name                 = var.subnet_name
  virtual_network_name = data.azurerm_virtual_network.main.name
  resource_group_name  = local.vnet_resource_group
}

###############################################################################
# Log Analytics Workspace (for monitoring)
###############################################################################

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-aks-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.tags
}

###############################################################################
# AKS Cluster with Spot Optimization
###############################################################################

module "aks" {
  source = "../../modules/aks-spot-optimized"

  cluster_name            = "${var.cluster_name_prefix}-${var.environment}"
  resource_group_name     = data.azurerm_resource_group.main.name
  location                = data.azurerm_resource_group.main.location
  kubernetes_version      = var.kubernetes_version
  vnet_subnet_id          = data.azurerm_subnet.aks.id
  os_sku                  = var.os_sku
  host_encryption_enabled = var.host_encryption_enabled
  tags                    = local.tags

  # Node pool configurations from variables
  system_pool_config    = var.system_pool_config
  standard_pool_configs = var.standard_pool_configs
  spot_pool_configs     = var.spot_pool_configs

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
  azure_ad_enabled       = true
  enable_rbac            = true
  admin_group_object_ids = var.admin_group_object_ids
}

###############################################################################
# Diagnostics - Event Capture for Observation
###############################################################################

module "diagnostics" {
  source = "../../modules/diagnostics"

  resource_group_name        = data.azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  aks_cluster_id             = module.aks.cluster_id
  subscription_id            = var.subscription_id
  environment                = var.environment
  tags                       = local.tags
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

