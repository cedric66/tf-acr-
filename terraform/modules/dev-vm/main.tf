terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.0"
    }
  }
}

locals {
  rg_name     = var.resource_group_name
  rg_location = var.location
}

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# Networking (Only created if subnet_id is not provided)
resource "azurerm_virtual_network" "vnet" {
  count               = var.subnet_id == null ? 1 : 0
  name                = "${var.vm_name}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = local.rg_location
  resource_group_name = local.rg_name
}

resource "azurerm_subnet" "subnet" {
  count                = var.subnet_id == null ? 1 : 0
  name                 = "${var.vm_name}-subnet"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_interface" "nic" {
  name                = "${var.vm_name}-nic"
  location            = local.rg_location
  resource_group_name = local.rg_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id == null ? azurerm_subnet.subnet[0].id : var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

data "azurerm_storage_account" "sa" {
  name                = var.storage_account_name
  resource_group_name = var.storage_account_rg
}

data "cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-init.yaml", {
      vk_username          = var.admin_username_vk,
      vk_key               = var.ssh_key_vk,
      sk_username          = var.admin_username_sk,
      storage_account_name = var.storage_account_name,
      storage_account_key  = data.azurerm_storage_account.sa.primary_access_key,
      file_share_name      = var.file_share_name,
      resource_group_name  = local.rg_name,
      vm_name              = var.vm_name
    })
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = local.rg_name
  location            = local.rg_location
  size                = var.vm_size
  admin_username      = var.admin_username_sk

  # Spot Instance Logic
  priority        = var.enable_spot ? "Spot" : "Regular"
  eviction_policy = var.enable_spot ? "Deallocate" : null
  max_bid_price   = var.enable_spot ? -1 : null # -1 means pay up to on-demand price

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  admin_ssh_key {
    username   = var.admin_username_sk
    public_key = var.ssh_key_sk
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = data.cloudinit_config.config.rendered

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  boot_diagnostics {
    storage_account_uri = null
  }
}

# Auto-shutdown at 7 PM on weekdays (Mon-Fri), all day weekends
resource "azurerm_dev_test_global_vm_shutdown_schedule" "shutdown" {
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id
  location           = local.rg_location
  enabled            = true

  daily_recurrence_time = "1900"
  timezone              = var.timezone

  notification_settings {
    enabled = false
  }

  tags = var.tags
}

# Auto-startup on weekdays at 8:15 AM using Azure Automation
resource "azurerm_automation_account" "automation" {
  count               = var.enable_auto_start ? 1 : 0
  name                = "${var.vm_name}-automation"
  location            = local.rg_location
  resource_group_name = local.rg_name
  sku_name            = "Basic"
  tags                = var.tags
}

resource "azurerm_automation_runbook" "start_vm" {
  count                   = var.enable_auto_start ? 1 : 0
  name                    = "StartVM"
  location                = local.rg_location
  resource_group_name     = local.rg_name
  automation_account_name = azurerm_automation_account.automation[0].name
  log_verbose             = false
  log_progress            = false
  runbook_type            = "PowerShell"

  content = <<-EOT
    param (
      [string]$ResourceGroupName,
      [string]$VMName
    )
    Connect-AzAccount -Identity
    Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
  EOT

  tags = var.tags
}

resource "azurerm_automation_schedule" "weekday_start" {
  count                   = var.enable_auto_start ? 1 : 0
  name                    = "WeekdayStart0815"
  resource_group_name     = local.rg_name
  automation_account_name = azurerm_automation_account.automation[0].name
  frequency               = "Week"
  interval                = 1
  timezone                = var.timezone
  start_time              = timeadd(timestamp(), "24h")
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "start_job" {
  count                   = var.enable_auto_start ? 1 : 0
  resource_group_name     = local.rg_name
  automation_account_name = azurerm_automation_account.automation[0].name
  schedule_name           = azurerm_automation_schedule.weekday_start[0].name
  runbook_name            = azurerm_automation_runbook.start_vm[0].name

  parameters = {
    resourcegroupname = local.rg_name
    vmname            = var.vm_name
  }
}

# Grant VM Contributor access to Resource Group (Required for self-tagging)
resource "azurerm_role_assignment" "vm_contributor" {
  scope                = data.azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_virtual_machine.vm.identity[0].principal_id
}
