output "acr_login_server" {
  description = "The URL of the Container Registry"
  value       = data.azurerm_container_registry.acr.login_server
}

output "acr_admin_username" {
  description = "The Admin Username for the Container Registry"
  value       = data.azurerm_container_registry.acr.admin_username
  sensitive   = true
}
