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

# OPTION B: AKS NODE AUTOPROVISIONING (KARPENTER)
# Note: This is currently in Preview.
resource "azurerm_kubernetes_cluster" "nap_enabled" {
  name                = "example-aks-nap"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  dns_prefix          = "exampleaksnap"

  # NETWORK REQUIREMENT FOR NAP: Azure CNI Overlay + Cilium
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    network_data_plane  = "cilium"
  }

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  # ENABLE NODE AUTOPROVISIONING
  node_provisioning_mode = "Auto"
}

# Note: Once Node Autoprovisioning is enabled, you typically configure NodePools 
# via Kubernetes Manifests (CRDs), NOT Terraform (yet), as the Karpenter 
# resources are Kubernetes objects, not Azure ARM resources.
#
# Below is a sample Kubernetes manifest for a Spot NodePool that you would apply
# via `kubectl apply` or the `kubernetes_manifest` terraform resource.

/*
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: spot-node-pool
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: kubernetes.azure.com/sku-family
          operator: In
          values: ["D", "E"] # Allow flexible SKU families
        - key: kubernetes.azure.com/sku-cpu
          operator: In
          values: ["2", "4", "8"] # Allow flexible CPU sizes
      nodeClassRef:
        name: default
  limits:
    cpu: 1000
    memory: 1000Gi
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
*/
