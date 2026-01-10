output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "storage_account_name" {
  value = module.storage.storage_account_name
}

output "share_name" {
  value = module.storage.share_name
}

output "acr_login_server" {
  value = module.acr.login_server
}
