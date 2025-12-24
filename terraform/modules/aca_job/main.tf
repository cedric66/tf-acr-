resource "azurerm_user_assigned_identity" "identity" {
  location            = var.location
  name                = "${var.job_name}-identity"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_push" {
  scope                = var.acr_id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.identity.principal_id
}

resource "azurerm_container_app_job" "build" {
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
      name    = "build-and-push"
      image   = "gcr.io/kaniko-project/executor:latest"
      cpu     = 0.5
      memory  = "1Gi"

      env {
        name  = "DOCKER_CONFIG"
        value = "/workspace/.docker"
      }

      args = [
        "--dockerfile=/workspace/app/${var.app_subdirectory}/Dockerfile",
        "--context=dir:///workspace/app/${var.app_subdirectory}",
        "--destination=${var.acr_login_server}/${var.image_name}:latest"
      ]

      volume_mounts {
        name = "source-code"
        path = "/workspace"
      }
    }

    init_container {
      name    = "setup-workspace"
      image   = "busybox"
      cpu     = 0.25
      memory  = "0.5Gi"

      # Combined command:
      # 1. Create directories.
      # 2. Unzip source.
      # 3. Create Docker config for Kaniko using credentials.
      command = ["sh", "-c", <<EOT
        mkdir -p /workspace/app
        mkdir -p /workspace/.docker
        unzip -o /mnt/source/${var.source_zip_filename} -d /workspace/app
        echo "{\"auths\":{\"${var.acr_login_server}\":{\"username\":\"${var.acr_username}\",\"password\":\"${var.acr_password}\"}}}" > /workspace/.docker/config.json
      EOT
      ]

      volume_mounts {
        name = "source-code"
        path = "/workspace"
      }
      volume_mounts {
        name = "azure-file-share"
        path = "/mnt/source"
      }
    }

    volume {
      name = "source-code"
      storage_type = "EmptyDir"
    }

    volume {
      name = "azure-file-share"
      storage_type = "AzureFile"
      storage_name = var.share_name
    }
  }

  # We can't strictly depend on the environment resource since it's in another module,
  # but we can depend on the environment ID being available.
  # However, to avoid the deletion ordering issue, we rely on Terraform's graph.
  # If the user destroys everything, the modules will be destroyed.
  # To satisfy the "must depend on env" requirement for 409 prevention:
  # Since the environment resource is not here, we can't reference it directly in `depends_on`.
  # BUT, we are passing `container_app_environment_id`. That creates an implicit dependency.
  # The 409 error earlier might have been because of the specific `azurerm` bug where implicit dependency wasn't enough for deletion order of Env vs Job.
  # If we separate them into modules, `aca_job` module depends on `aca_env` module.
  # Terraform *should* destroy `aca_job` first.
}
