resource "azurerm_log_analytics_workspace" "law" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_log_analytics_workspace_table" "container_log" {
  workspace_id = azurerm_log_analytics_workspace.law.id
  name         = "ContainerLog"
  plan         = "Basic"
}
