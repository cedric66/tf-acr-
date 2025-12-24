resource "azurerm_container_app_environment" "env" {
  name                       = var.env_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = var.log_analytics_workspace_id
  tags                       = var.tags
}

resource "azurerm_container_app_environment_storage" "mount" {
  name                         = var.share_name
  container_app_environment_id = azurerm_container_app_environment.env.id
  account_name                 = var.storage_account_name
  share_name                   = var.share_name
  access_key                   = var.storage_account_key
  access_mode                  = "ReadOnly"
}
