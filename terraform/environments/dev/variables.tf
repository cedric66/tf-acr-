variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  default     = null # Can be supplied via env var or tfvars
}

variable "resource_group_name" {
  description = "Name of the existing resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "subnet_id" {
  description = "Existing Subnet ID (optional). If provided, VM is attached to it. If not, a new VNet/Subnet is created."
  type        = string
  default     = null
}

variable "ssh_key_sk_path" {
  description = "Path to public key for user sk"
  type        = string
  default     = "../../../keys/sk.pub"
}

variable "ssh_key_vk_path" {
  description = "Path to public key for user vk"
  type        = string
  default     = "../../../keys/vk.pub"
}

variable "storage_account_name" {
  description = "Name of the storage account for Cloud Drive"
  type        = string
}

variable "storage_account_rg" {
  description = "Resource Group of the storage account"
  type        = string
}

variable "file_share_name" {
  description = "Name of the Azure File Share to mount"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply (will override defaults if keys conflict)"
  type        = map(string)
  default     = {}
}

variable "vm_size" {
  description = "Size of the VM (e.g., Standard_B2s, Standard_D2s_v3)"
  type        = string
  default     = "Standard_B2s"
}

variable "enable_spot" {
  description = "Enable Azure Spot Instance"
  type        = bool
  default     = false
}
