###############################################################################
# Diagnostics Module - Main Configuration
# Purpose: Export Activity Log and AKS diagnostics to Log Analytics for review
###############################################################################

terraform {
  required_version = ">= 1.5.0"
}

###############################################################################
# Variables
###############################################################################

variable "resource_group_name" {
  description = "Resource group containing the AKS cluster"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID to export logs to"
  type        = string
}

variable "aks_cluster_id" {
  description = "AKS cluster resource ID"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID for Activity Log export"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}

###############################################################################
# Data Sources
###############################################################################

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

###############################################################################
# Activity Log Export (Subscription Level)
# Captures: VMSS failures, AKS operations, scaling events
###############################################################################

resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "diag-activity-log-${var.environment}"
  target_resource_id         = "/subscriptions/${var.subscription_id}"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "Administrative"
  }

  enabled_log {
    category = "Security"
  }

  enabled_log {
    category = "Alert"
  }

  enabled_log {
    category = "Autoscale"
  }

  enabled_log {
    category = "Policy"
  }
}

###############################################################################
# AKS Diagnostics
# Captures: kube-audit, cluster-autoscaler, kube-controller-manager
###############################################################################

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-aks-${var.environment}"
  target_resource_id         = var.aks_cluster_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Control plane logs
  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  enabled_log {
    category = "guard"
  }

  # Metrics
  # Metrics
  enabled_metric {
    category = "AllMetrics"
  }
}

###############################################################################
# Outputs
###############################################################################

output "activity_log_diagnostic_id" {
  description = "ID of the Activity Log diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.activity_log.id
}

output "aks_diagnostic_id" {
  description = "ID of the AKS diagnostic setting"
  value       = azurerm_monitor_diagnostic_setting.aks.id
}
