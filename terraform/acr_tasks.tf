locals {
  apps      = ["java", "springboot", "nodejs", "go", "python"]
  providers = ["chainguard", "minimus", "dhi", "alpine", "ubi"]

  # Flatten logic for all combinations
  image_variants = flatten([
    for app in local.apps : [
      for prov in local.providers : {
        name = "${app}-${prov}"
        app  = app
        prov = prov
      }
    ]
  ])
}

# Example ACR Task to build the images
# This resource iterates over the local.image_variants map.
resource "azurerm_container_registry_task" "build_tasks" {
  for_each              = { for v in local.image_variants : v.name => v }
  name                  = "build-${each.value.name}"
  container_registry_id = data.azurerm_container_registry.acr.id

  platform {
    os = "Linux"
  }

  docker_step {
    dockerfile_path = "image_evaluation/dockerfiles/${each.value.app}/Dockerfile.${each.value.prov}"
    context_path    = "https://github.com/USER/REPO#main" # Placeholder: Update with actual Git repo and branch
    context_access_token = "GIT_PAT_PLACEHOLDER"          # Placeholder: Update with valid PAT or remove if public
    
    image_names = ["${each.value.name}:{{.Run.ID}}", "${each.value.name}:latest"]
  }

  agent_setting {
    cpu = 2
  }
}
