variable "job_name" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.job_name))
    error_message = "Container App Job name must consist of lowercase alphanumeric characters or hyphens, start and end with an alphanumeric character, and be less than 32 characters."
  }
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "container_app_environment_id" {
  type = string
}

variable "acr_id" {
  type = string
}

variable "acr_login_server" {
  type = string
}

variable "acr_username" {
  type = string
  sensitive = true
}

variable "acr_password" {
  type = string
  sensitive = true
}

variable "share_name" {
  type = string
}

variable "image_to_scan" {
  type = string
  description = "Full image reference (e.g. server.azurecr.io/python:latest) to scan"
}

variable "tags" {
  type    = map(string)
  default = {}
}
