terraform {
  required_version = ">= 1.0"
}

module "dev_vm" {
  source = "../../modules/dev-vm"

  resource_group_name = var.resource_group_name
  location            = var.location
  resource_group_name = var.resource_group_name
  location            = var.location
  vm_name             = "azure-devbox"
  vm_size             = var.vm_size
  enable_spot         = var.enable_spot

  admin_username_sk = "sk"
  ssh_key_sk        = file(var.ssh_key_sk_path)

  admin_username_vk = "vk"
  ssh_key_vk        = file(var.ssh_key_vk_path)

  storage_account_name = var.storage_account_name
  storage_account_rg   = var.storage_account_rg
  file_share_name      = var.file_share_name

  subnet_id = var.subnet_id

  tags = merge(
    {
      environment = "dev"
      purpose     = "developer-vm"
      owner       = "devops-team"
    },
    var.tags
  )
}

output "vm_private_ip" {
  value = module.dev_vm.private_ip
}

output "vm_id" {
  value = module.dev_vm.vm_id
}

output "vm_principal_id" {
  description = "Managed Identity Principal ID for role assignments"
  value       = module.dev_vm.principal_id
}
