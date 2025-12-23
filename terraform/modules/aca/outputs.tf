output "environment_id" {
  value = azurerm_container_app_environment.env.id
}

output "job_id" {
  value = azurerm_container_app_job.build.id
}
