variable "resource_group_name" {
  description = "Name of the resource group"
  default     = "rg-aca-build-dev-eus"
  validation {
    condition     = can(regex("^rg-", var.resource_group_name))
    error_message = "Resource group name must start with 'rg-'."
  }
}

variable "location" {
  description = "Azure region"
  default     = "eastus"
}

variable "acr_name" {
  description = "Name of the ACR"
  default     = "acracabuilddeveus"
  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.acr_name))
    error_message = "ACR name must contain only alphanumeric characters."
  }
}

variable "storage_account_name" {
  description = "Name of the Storage Account"
  default     = "stacabuilddeveus"
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be between 3 and 24 characters and contain only lowercase letters and numbers."
  }
}

variable "share_name" {
  description = "Name of the File Share"
  default     = "share-aca-build-dev"
}

variable "env_name" {
  description = "Name of the Container Apps Environment"
  default     = "cae-aca-build-dev-eus"
  validation {
    condition     = can(regex("^cae-", var.env_name))
    error_message = "Container App Environment name must start with 'cae-'."
  }
}

variable "job_name_prefix" {
  description = "Prefix for Container Apps Job Name"
  default     = "caj-aca-build-dev-eus"
  validation {
    condition     = can(regex("^caj-", var.job_name_prefix))
    error_message = "Container App Job name prefix must start with 'caj-'."
  }
}

variable "log_analytics_name" {
  description = "Name of the Log Analytics Workspace"
  default     = "log-aca-build-dev-eus"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "budget_alert_emails" {
  description = "List of emails to notify when budget is exceeded"
  type        = list(string)
}
