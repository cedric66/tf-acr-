variable "resource_group_name" {
  description = "Name of the resource group"
  default     = "rg-dev-aca-build"
}

variable "location" {
  description = "Azure region"
  default     = "eastus"
}

variable "acr_name" {
  description = "Name of the ACR"
  default     = "acrdevbuild001"
}

variable "storage_account_name" {
  description = "Name of the Storage Account"
  default     = "stdevbuild001"
}

variable "share_name" {
  description = "Name of the File Share"
  default     = "build-context"
}

variable "env_name" {
  description = "Name of the Container Apps Environment"
  default     = "cae-dev-build"
}

variable "job_name" {
  description = "Name of the Container Apps Job"
  default     = "caj-dev-build-image"
}
