resource "azurerm_user_assigned_identity" "identity" {
  location            = var.location
  name                = "${var.job_name}-id"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.identity.principal_id
}

resource "azurerm_container_app_job" "scan" {
  name                = var.job_name
  location            = var.location
  resource_group_name = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  tags                = var.tags

  replica_timeout_in_seconds = 1800
  replica_retry_limit        = 0
  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.identity.id]
  }

  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.identity.id
  }

  template {
    container {
      name    = "scanner"
      image   = "anchore/grype:latest"
      cpu     = 0.5
      memory  = "1Gi"

      # Grype will use the registry identity automatically
      # No need for DOCKER_CONFIG when using managed identity

      args = [
        "registry:${var.image_to_scan}",
        "-o", "json",
        "--file", "/mnt/reports/${var.job_name}.json"
      ]

      volume_mounts {
        name = "azure-file-share"
        path = "/mnt/reports"
      }
    }

    init_container {
      name    = "setup-reports-dir"
      image   = "busybox"
      cpu     = 0.25
      memory  = "0.5Gi"

      command = ["sh", "-c", "mkdir -p /mnt/reports"]

      volume_mounts {
        name = "azure-file-share"
        path = "/mnt/reports"
      }
    }

    volume {
      name = "azure-file-share"
      storage_type = "AzureFile"
      storage_name = var.share_name
    }
  }

  # Ensure role assignment is completed before job is created
  depends_on = [azurerm_role_assignment.acr_pull]
}
