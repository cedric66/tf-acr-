output "storage_account_name" {
  value = azurerm_storage_account.sa.name
}

output "storage_account_key" {
  value = azurerm_storage_account.sa.primary_access_key
  sensitive = true
}

output "share_name" {
  value = azurerm_storage_share.share.name
}

output "share_id" {
  value = azurerm_storage_share.share.id
}
