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
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.34"
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
# Tags
###############################################################################

variable "extra_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
