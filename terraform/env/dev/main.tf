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

module "aca" {
  source              = "../../modules/aca"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  env_name            = var.env_name
  job_name            = var.job_name
  acr_id              = module.acr.id
  acr_login_server    = module.acr.login_server
  acr_username        = module.acr.admin_username
  acr_password        = module.acr.admin_password
  storage_account_name = module.storage.storage_account_name
  storage_account_key  = module.storage.storage_account_key
  share_name           = module.storage.share_name
  source_zip_filename  = "app.zip"
  tags                 = var.tags
}
