resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "acr" {
  source              = "../../modules/acr"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  acr_name            = var.acr_name
  tags                = var.tags
}

module "storage" {
  source               = "../../modules/storage"
  resource_group_name  = azurerm_resource_group.rg.name
  location             = azurerm_resource_group.rg.location
  storage_account_name = var.storage_account_name
  share_name           = var.share_name
  tags                 = var.tags
}

module "log_analytics" {
  source              = "../../modules/log_analytics"
  name                = var.log_analytics_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = var.tags
}

data "archive_file" "app_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../../app"
  output_path = "${path.module}/app.zip"
}

resource "azurerm_storage_share_file" "source_code" {
  name             = "app.zip"
  storage_share_id = module.storage.share_id
  source           = data.archive_file.app_zip.output_path
}

module "aca_env" {
  source                     = "../../modules/aca_env"
  env_name                   = var.env_name
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  log_analytics_workspace_id = module.log_analytics.id
  storage_account_name       = module.storage.storage_account_name
  storage_account_key        = module.storage.storage_account_key
  share_name                 = module.storage.share_name
  tags                       = var.tags
}

# Image Import Job
module "aca_job_import" {
  source                       = "../../modules/aca_job_import"
  job_name                     = "${var.job_name_prefix}-import"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  container_app_environment_id = module.aca_env.id
  acr_id                       = module.acr.id
  acr_login_server             = module.acr.login_server
  acr_username                 = module.acr.admin_username
  acr_password                 = module.acr.admin_password
  images_to_copy               = var.images_to_import
  tags                         = var.tags
}

# Java Job
module "aca_job_java" {
  source                       = "../../modules/aca_job"
  job_name                     = "${var.job_name_prefix}-java"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  container_app_environment_id = module.aca_env.id
  acr_id                       = module.acr.id
  acr_login_server             = module.acr.login_server
  acr_username                 = module.acr.admin_username
  acr_password                 = module.acr.admin_password
  share_name                   = module.storage.share_name
  source_zip_filename          = "app.zip"
  app_subdirectory             = "java"
  image_name                   = "my-java-app"
  build_args                   = {
    "BUILD_IMAGE" = "${module.acr.login_server}/maven:3.9-eclipse-temurin-17"
    "RUN_IMAGE"   = "${module.acr.login_server}/chainguard/jre:latest"
  }
  tags                         = var.tags
}

# Go Job
module "aca_job_go" {
  source                       = "../../modules/aca_job"
  job_name                     = "${var.job_name_prefix}-go"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  container_app_environment_id = module.aca_env.id
  acr_id                       = module.acr.id
  acr_login_server             = module.acr.login_server
  acr_username                 = module.acr.admin_username
  acr_password                 = module.acr.admin_password
  share_name                   = module.storage.share_name
  source_zip_filename          = "app.zip"
  app_subdirectory             = "go"
  image_name                   = "my-go-app"
  build_args                   = {
    "BUILD_IMAGE" = "${module.acr.login_server}/chainguard/go:latest"
    "RUN_IMAGE"   = "${module.acr.login_server}/chainguard/static:latest"
  }
  tags                         = var.tags
}

# Python Job
module "aca_job_python" {
  source                       = "../../modules/aca_job"
  job_name                     = "${var.job_name_prefix}-python"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  container_app_environment_id = module.aca_env.id
  acr_id                       = module.acr.id
  acr_login_server             = module.acr.login_server
  acr_username                 = module.acr.admin_username
  acr_password                 = module.acr.admin_password
  share_name                   = module.storage.share_name
  source_zip_filename          = "app.zip"
  app_subdirectory             = "python"
  image_name                   = "my-python-app"
  build_args                   = {
    "RUN_IMAGE"   = "${module.acr.login_server}/chainguard/python:latest"
  }
  tags                         = var.tags
}

# Node Job
module "aca_job_node" {
  source                       = "../../modules/aca_job"
  job_name                     = "${var.job_name_prefix}-node"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  container_app_environment_id = module.aca_env.id
  acr_id                       = module.acr.id
  acr_login_server             = module.acr.login_server
  acr_username                 = module.acr.admin_username
  acr_password                 = module.acr.admin_password
  share_name                   = module.storage.share_name
  source_zip_filename          = "app.zip"
  app_subdirectory             = "node"
  image_name                   = "my-node-app"
  build_args                   = {
    "RUN_IMAGE"   = "${module.acr.login_server}/chainguard/node:latest"
  }
  tags                         = var.tags
}

# DHI Go Job
module "aca_job_dhi_go" {
  source                       = "../../modules/aca_job"
  job_name                     = "${var.job_name_prefix}-dhi-go"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  container_app_environment_id = module.aca_env.id
  acr_id                       = module.acr.id
  acr_login_server             = module.acr.login_server
  acr_username                 = module.acr.admin_username
  acr_password                 = module.acr.admin_password
  share_name                   = module.storage.share_name
  source_zip_filename          = "app.zip"
  app_subdirectory             = "dhi-go"
  image_name                   = "my-dhi-go-app"
  build_args                   = {
    "BUILD_IMAGE" = "${module.acr.login_server}/golang:1.21-alpine"
    "RUN_IMAGE"   = "${module.acr.login_server}/distroless/static:nonroot"
  }
  tags                         = var.tags
}

module "budget" {
  source            = "../../modules/budget"
  resource_group_id = azurerm_resource_group.rg.id
  contact_emails    = var.budget_alert_emails
}
