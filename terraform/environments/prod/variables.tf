###############################################################################
# Production Environment Variables
# Purpose: Define input variables for the production AKS cluster
###############################################################################

###############################################################################
# Azure Subscription & Provider
###############################################################################

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

###############################################################################
# Existing Resource References
###############################################################################

variable "resource_group_name" {
  description = "Name of the existing resource group for AKS deployment"
  type        = string
}

variable "vnet_name" {
  description = "Name of the existing virtual network"
  type        = string
}

variable "vnet_resource_group_name" {
  description = "Resource group containing the virtual network (if different from AKS resource group)"
  type        = string
  default     = null # If null, uses resource_group_name
}

variable "subnet_name" {
  description = "Name of the existing subnet for AKS nodes"
  type        = string
}

###############################################################################
# Cluster Configuration
###############################################################################

variable "environment" {
  description = "Environment name (e.g., prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "australiaeast"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster (check: az aks get-versions -l <location>)"
  type        = string
  default     = "1.34"

  validation {
    condition     = can(regex("^1\\.(3[0-9]|[4-9][0-9])$", var.kubernetes_version))
    error_message = "Kubernetes version must be 1.30 or higher (e.g., 1.34, 1.35)."
  }
}

variable "cluster_name_prefix" {
  description = "Prefix for the AKS cluster name"
  type        = string
  default     = "aks-spot"
}

###############################################################################
# Optional Features
###############################################################################

variable "os_sku" {
  description = "OS SKU for node pools (Ubuntu, Ubuntu2404, AzureLinux)"
  type        = string
  default     = "Ubuntu"
}

variable "host_encryption_enabled" {
  description = "Enable host-based encryption for node pools"
  type        = bool
  default     = false
}

variable "log_analytics_retention_days" {
  description = "Retention period for Log Analytics workspace in days"
  type        = number
  default     = 30
}

###############################################################################
# Node Pool Configurations
###############################################################################

variable "system_pool_config" {
  description = "System node pool configuration"
  type = object({
    name                = string
    vm_size             = string
    min_count           = number
    max_count           = number
    zones               = list(string)
    os_disk_size_gb     = number
    enable_auto_scaling = bool
  })
  default = {
    name                = "system"
    vm_size             = "Standard_D4s_v5"
    min_count           = 3
    max_count           = 5
    zones               = ["1", "2", "3"]
    os_disk_size_gb     = 128
    enable_auto_scaling = true
  }
}

variable "standard_pool_configs" {
  description = "Standard (on-demand) node pool configurations"
  type = list(object({
    name                = string
    vm_size             = string
    min_count           = number
    max_count           = number
    zones               = list(string)
    os_disk_size_gb     = number
    enable_auto_scaling = bool
    labels              = optional(map(string), {})
  }))
  default = [
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
}

variable "spot_pool_configs" {
  description = "Spot node pool configurations"
  type = list(object({
    name            = string
    vm_size         = string
    min_count       = number
    max_count       = number
    zones           = list(string)
    spot_max_price  = number
    eviction_policy = string
    priority_weight = number
    labels          = optional(map(string), {})
  }))
  default = [
    {
      name            = "spotgen1"
      vm_size         = "Standard_D4s_v5"
      min_count       = 0
      max_count       = 25
      zones           = ["1"]
      spot_max_price  = -1
      eviction_policy = "Delete"
      priority_weight = 10
      labels = {
        "spot-pool-id" = "1"
        "vm-family"    = "general"
      }
    },
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
}

###############################################################################
# AAD & RBAC
###############################################################################

variable "admin_group_object_ids" {
  description = "Azure AD group object IDs for cluster admin access"
  type        = list(string)
  default     = []
}

###############################################################################
# Tags
###############################################################################

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
