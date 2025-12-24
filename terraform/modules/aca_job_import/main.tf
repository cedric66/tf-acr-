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

resource "azurerm_container_app_job" "import" {
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
      name    = "image-importer"
      image   = "gcr.io/go-containerregistry/crane:debug"
      cpu     = 0.5
      memory  = "1Gi"

      # We construct a shell command to loop through the map of images.
      # Since we can't easily pass a complex map to env vars, we will pass a delimited string or just hardcode the logic in the command using the variable interpolation.
      command = ["/bin/sh", "-c", <<EOT
        # Login to ACR using the identity (via config or helper if available, but crane supports basic auth too).
        # Since we are inside ACA with Managed Identity and 'registry' block configured,
        # ACA handles the pull of the 'crane' image (if it were private).
        # For pushing, 'crane' needs credentials.
        # We can use the ACR admin credentials passed in vars.

        crane auth login ${var.acr_login_server} -u ${var.acr_username} -p ${var.acr_password}

        %{ for src, dest in var.images_to_copy }
        echo "Copying ${src} to ${var.acr_login_server}/${dest}..."
        crane copy ${src} ${var.acr_login_server}/${dest}
        %{ endfor }

        echo "Image import complete."
      EOT
      ]
    }
  }
}
