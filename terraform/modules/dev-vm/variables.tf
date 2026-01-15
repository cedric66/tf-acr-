variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "vm_name" {
  description = "Name of the VM"
  type        = string
  default     = "dev-vm"
}

variable "vm_size" {
  description = "Size of the VM"
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username_sk" {
  description = "Username for the first user"
  type        = string
  default     = "sk"
}

variable "ssh_key_sk" {
  description = "Public SSH key for user sk"
  type        = string
}

variable "admin_username_vk" {
  description = "Username for the second user"
  type        = string
  default     = "vk"
}

variable "ssh_key_vk" {
  description = "Public SSH key for user vk"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID to deploy the VM into. If null, a new VNet and Subnet will be created."
  type        = string
  default     = null
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
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    environment = "dev"
    purpose     = "developer-vm"
  }
}

variable "timezone" {
  description = "Timezone for auto-shutdown schedule (Windows format, e.g., 'Singapore Standard Time')"
  type        = string
  default     = "Singapore Standard Time"
}

variable "timezone_iana" {
  description = "Timezone for automation schedule (IANA/Olson format, e.g., 'Asia/Singapore')"
  type        = string
  default     = "Asia/Singapore"
}

variable "enable_auto_start" {
  description = "Enable automatic startup on weekdays at 8:15 AM"
  type        = bool
  default     = true
}

variable "enable_spot" {
  description = "Enable Azure Spot Instance for cost savings"
  type        = bool
  default     = false
}
