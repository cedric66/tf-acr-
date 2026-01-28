###############################################################################
# AKS Spot-Optimized Module - Variables
# Purpose: Define all configurable parameters for spot node pool optimization
###############################################################################

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group containing the AKS cluster"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.28"
}

variable "vnet_subnet_id" {
  description = "ID of the subnet for node pools"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

###############################################################################
# System Node Pool Configuration
###############################################################################

variable "system_pool_config" {
  description = "Configuration for the system node pool"
  type = object({
    name                = optional(string, "system")
    vm_size             = optional(string, "Standard_D4s_v5")
    node_count          = optional(number, 3)
    min_count           = optional(number, 3)
    max_count           = optional(number, 6)
    zones               = optional(list(string), ["1", "2", "3"])
    os_disk_size_gb     = optional(number, 128)
    os_disk_type        = optional(string, "Managed")
    enable_auto_scaling = optional(bool, true)
    max_pods            = optional(number, 50)
    labels              = optional(map(string), {})
  })
  default = {}
}

###############################################################################
# Standard Workload Node Pool Configuration
###############################################################################

variable "standard_pool_configs" {
  description = "Configuration for standard (on-demand) node pools for fallback"
  type = list(object({
    name                = string
    vm_size             = optional(string, "Standard_D4s_v5")
    min_count           = optional(number, 2)
    max_count           = optional(number, 10)
    zones               = optional(list(string), ["1", "2"])
    os_disk_size_gb     = optional(number, 128)
    os_disk_type        = optional(string, "Managed")
    enable_auto_scaling = optional(bool, true)
    max_pods            = optional(number, 50)
    labels              = optional(map(string), {})
    taints              = optional(list(string), [])
  }))
  default = [
    {
      name      = "stdworkload"
      vm_size   = "Standard_D4s_v5"
      min_count = 2
      max_count = 10
      zones     = ["1", "2"]
    }
  ]
}

###############################################################################
# Spot Node Pool Configuration
###############################################################################

variable "spot_pool_configs" {
  description = "Configuration for spot node pools with diversified VM sizes"
  type = list(object({
    name                 = string
    vm_size              = string
    min_count            = optional(number, 0)
    max_count            = optional(number, 20)
    zones                = optional(list(string), ["1"])
    os_disk_size_gb      = optional(number, 128)
    os_disk_type         = optional(string, "Managed")
    enable_auto_scaling  = optional(bool, true)
    max_pods             = optional(number, 50)
    spot_max_price       = optional(number, -1)  # -1 = up to on-demand price
    eviction_policy      = optional(string, "Delete")
    labels               = optional(map(string), {})
    taints               = optional(list(string), [])
    priority_weight      = optional(number, 10)  # For expander priority
  }))
  default = [
    # General purpose D-series pool (Zone 1)
    {
      name      = "spotgeneral1"
      vm_size   = "Standard_D4s_v5"   # 4 vCPU, 16 GB RAM - general purpose
      min_count = 0
      max_count = 20
      zones     = ["1"]
    },
    # Memory-optimized E-series pool (Zone 2)
    # E-series has LOWER spot competition than D-series per LinkedIn case study
    {
      name      = "spotmemory1"
      vm_size   = "Standard_E4s_v5"   # 4 vCPU, 32 GB RAM - memory optimized, lower eviction risk
      min_count = 0
      max_count = 15
      zones     = ["2"]
      priority_weight = 5             # Higher priority (lower number) - prefer memory VMs
    },
    # Larger general purpose pool (Zone 2)
    {
      name      = "spotgeneral2"
      vm_size   = "Standard_D8s_v5"   # 8 vCPU, 32 GB RAM - larger general purpose
      min_count = 0
      max_count = 15
      zones     = ["2"]
      priority_weight = 10
    },
    # Compute-optimized F-series pool (Zone 3)
    {
      name      = "spotcompute"
      vm_size   = "Standard_F8s_v2"   # 8 vCPU, 16 GB RAM - compute optimized
      min_count = 0
      max_count = 10
      zones     = ["3"]
      priority_weight = 10
    },
    # Additional memory-optimized pool (Zone 3) for diversity
    {
      name      = "spotmemory2"
      vm_size   = "Standard_E8s_v5"   # 8 vCPU, 64 GB RAM - large memory workloads
      min_count = 0
      max_count = 10
      zones     = ["3"]
      priority_weight = 5             # Prefer memory VMs
    }
  ]
}

###############################################################################
# Cluster Autoscaler Configuration
# Optimized for bursty/spot workloads per Microsoft recommendation:
# https://learn.microsoft.com/en-us/azure/aks/cluster-autoscaler
###############################################################################

variable "autoscaler_profile" {
  description = "Cluster autoscaler profile settings optimized for spot instances and bursty workloads"
  type = object({
    balance_similar_node_groups      = optional(bool, true)
    expander                         = optional(string, "priority")
    max_graceful_termination_sec     = optional(number, 60)           # Increased from 30s for graceful shutdown
    max_node_provisioning_time       = optional(string, "15m")
    max_unready_nodes                = optional(number, 3)
    max_unready_percentage           = optional(number, 45)
    new_pod_scale_up_delay           = optional(string, "0s")
    scale_down_delay_after_add       = optional(string, "10m")
    scale_down_delay_after_delete    = optional(string, "10s")
    scale_down_delay_after_failure   = optional(string, "3m")
    scale_down_unneeded              = optional(string, "5m")          # Faster scale-down per bursty profile
    scale_down_unready               = optional(string, "5m")          # Faster unready scale-down
    scale_down_utilization_threshold = optional(number, 0.5)
    scan_interval                    = optional(string, "20s")         # MS recommended for bursty workloads (was 10s)
    skip_nodes_with_local_storage    = optional(bool, false)
    skip_nodes_with_system_pods      = optional(bool, true)
    # New settings GA in API 2024-05-01
    ignore_daemonsets_utilization        = optional(bool, false)
    daemonset_eviction_for_empty_nodes   = optional(bool, false)
    daemonset_eviction_for_occupied_nodes = optional(bool, true)
  })
  default = {}
}

###############################################################################
# Network Profile
###############################################################################

variable "network_profile" {
  description = "Network profile for the AKS cluster"
  type = object({
    network_plugin      = optional(string, "azure")
    network_policy      = optional(string, "calico")
    dns_service_ip      = optional(string)
    service_cidr        = optional(string)
    load_balancer_sku   = optional(string, "standard")
    outbound_type       = optional(string, "loadBalancer")
  })
  default = {}
}

###############################################################################
# Identity and RBAC
###############################################################################

variable "identity_type" {
  description = "Type of identity for the AKS cluster"
  type        = string
  default     = "SystemAssigned"
}

variable "enable_rbac" {
  description = "Enable Kubernetes RBAC"
  type        = bool
  default     = true
}

variable "azure_ad_enabled" {
  description = "Enable Azure AD integration"
  type        = bool
  default     = true
}

variable "admin_group_object_ids" {
  description = "List of Azure AD group object IDs for cluster admin access"
  type        = list(string)
  default     = []
}

###############################################################################
# Monitoring and Logging
###############################################################################

variable "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace for monitoring"
  type        = string
  default     = null
}

variable "enable_azure_monitor" {
  description = "Enable Azure Monitor for containers"
  type        = bool
  default     = true
}

###############################################################################
# Priority Expander Deployment
###############################################################################

variable "deploy_priority_expander" {
  description = "Automatically deploy the cluster-autoscaler-priority-expander ConfigMap. Requires Kubernetes provider to be configured."
  type        = bool
  default     = false
}
