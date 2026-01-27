###############################################################################
# Production Environment Variables
# Purpose: Define input variables for the production AKS cluster
###############################################################################

variable "resource_group_name" {
  description = "Override the default resource group name"
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "Override the default cluster name"
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "australiaeast"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "1.28"
}
