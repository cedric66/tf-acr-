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
  name                = "${var.env_name}-logs"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags                = var.tags
}

module "aca_env" {
  source                     = "../../modules/aca_env"
  env_name                   = var.env_name
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = var.tags
}

# --- Python ---
module "job_build_python" {
  source = "../../modules/aca_job"
  job_name = "build-python"
  resource_group_name = azurerm_resource_group.rg.name
  location = var.location
  container_app_environment_id = module.aca_env.id
  acr_id = module.acr.id
  acr_login_server = module.acr.login_server
  acr_username = module.acr.admin_username
  acr_password = module.acr.admin_password
  share_name = module.storage.share_name
  source_zip_filename = "app.zip"
  app_subdirectory = "python-app"
  image_name = "python-app"
  tags = var.tags
}
module "job_scan_python" {
  source = "../../modules/aca_scanner_job"
  job_name = "scan-python"
  resource_group_name = azurerm_resource_group.rg.name
  location = var.location
  container_app_environment_id = module.aca_env.id
  acr_id = module.acr.id
  acr_login_server = module.acr.login_server
  acr_username = module.acr.admin_username
  acr_password = module.acr.admin_password
  share_name = module.storage.share_name
  image_to_scan = "${module.acr.login_server}/python-app:latest"
  tags = var.tags
}

# --- Node ---
module "job_build_node" {
  source = "../../modules/aca_job"
  job_name = "build-node"
  resource_group_name = azurerm_resource_group.rg.name
  location = var.location
  container_app_environment_id = module.aca_env.id
  acr_id = module.acr.id
  acr_login_server = module.acr.login_server
  acr_username = module.acr.admin_username
  acr_password = module.acr.admin_password
  share_name = module.storage.share_name
  source_zip_filename = "app.zip"
  app_subdirectory = "nodejs-app"
  image_name = "nodejs-app"
  tags = var.tags
}
module "job_scan_node" {
  source = "../../modules/aca_scanner_job"
  job_name = "scan-node"
  resource_group_name = azurerm_resource_group.rg.name
  location = var.location
  container_app_environment_id = module.aca_env.id
  acr_id = module.acr.id
  acr_login_server = module.acr.login_server
  acr_username = module.acr.admin_username
  acr_password = module.acr.admin_password
  share_name = module.storage.share_name
  image_to_scan = "${module.acr.login_server}/nodejs-app:latest"
  tags = var.tags
}

# --- Java ---
module "job_build_java" {
  source = "../../modules/aca_job"
  job_name = "build-java"
  resource_group_name = azurerm_resource_group.rg.name
  location = var.location
  container_app_environment_id = module.aca_env.id
  acr_id = module.acr.id
  acr_login_server = module.acr.login_server
  acr_username = module.acr.admin_username
  acr_password = module.acr.admin_password
  share_name = module.storage.share_name
  source_zip_filename = "app.zip"
  app_subdirectory = "java-app"
  image_name = "java-app"
  tags = var.tags
}
module "job_scan_java" {
  source = "../../modules/aca_scanner_job"
  job_name = "scan-java"
  resource_group_name = azurerm_resource_group.rg.name
  location = var.location
  container_app_environment_id = module.aca_env.id
  acr_id = module.acr.id
  acr_login_server = module.acr.login_server
  acr_username = module.acr.admin_username
  acr_password = module.acr.admin_password
  share_name = module.storage.share_name
  image_to_scan = "${module.acr.login_server}/java-app:latest"
  tags = var.tags
}

# --- Go ---
module "job_build_go" {
  source = "../../modules/aca_job"
  job_name = "build-go"
  resource_group_name = azurerm_resource_group.rg.name
  location = var.location
  container_app_environment_id = module.aca_env.id
  acr_id = module.acr.id
  acr_login_server = module.acr.login_server
  acr_username = module.acr.admin_username
  acr_password = module.acr.admin_password
  share_name = module.storage.share_name
  source_zip_filename = "app.zip"
  app_subdirectory = "go-app"
  image_name = "go-app"
  tags = var.tags
}
module "job_scan_go" {
  source = "../../modules/aca_scanner_job"
  job_name = "scan-go"
  resource_group_name = azurerm_resource_group.rg.name
  location = var.location
  container_app_environment_id = module.aca_env.id
  acr_id = module.acr.id
  acr_login_server = module.acr.login_server
  acr_username = module.acr.admin_username
  acr_password = module.acr.admin_password
  share_name = module.storage.share_name
  image_to_scan = "${module.acr.login_server}/go-app:latest"
  tags = var.tags
}

module "budget" {
  source            = "../../modules/budget"
  resource_group_id = azurerm_resource_group.rg.id
  contact_emails    = var.budget_alert_emails
}
