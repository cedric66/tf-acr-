variable "env_name" {
  type = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,32}$", var.env_name))
    error_message = "Container App Environment name must be between 2 and 32 characters and contain only alphanumeric characters and hyphens."
  }
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "storage_account_key" {
  type = string
}

variable "share_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
