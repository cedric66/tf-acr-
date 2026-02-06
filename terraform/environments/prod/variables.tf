###############################################################################
# Production Environment Variables
# Purpose: Define input variables for the production AKS cluster
###############################################################################

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
