terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "example" {
  name     = "example-resources"
  location = "West Europe"
}

resource "azurerm_kubernetes_cluster" "example" {
  name                = "example-aks1"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  dns_prefix          = "exampleaks1"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
}

# OPTION A: NATIVE AKS SPOT NODE POOL
# This uses VMSS under the hood.
resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  name                  = "spotpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.example.id
  vm_size               = "Standard_DS2_v2" 
  node_count            = 1
  
  # Enable Autoscaling (Best Practice for Spot)
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 5

  # SPOT CONFIGURATION
  priority        = "Spot"
  eviction_policy = "Delete" # Recommended for autoscaling
  spot_max_price  = -1       # -1 means market price, capped at standard price

  # Taints to prevent critical system pods from scheduling here
  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  # Labels for node affinity/selectors
  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
    "workload_type"                         = "batch_processing"
  }

  tags = {
    Environment = "Dev"
  }
}
