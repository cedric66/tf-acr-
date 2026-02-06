// =============================================================================
// Production Environment Parameters
// Purpose: Mirror terraform.tfvars.example configuration
// =============================================================================

using '../../main.bicep'

// =============================================================================
// Required Parameters
// =============================================================================

param clusterName = 'aks-spot-prod'
param kubernetesVersion = '1.34'
param location = 'australiaeast'

// Replace with your actual subnet resource ID
param vnetSubnetId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-aks/subnets/snet-aks'

// =============================================================================
// System Node Pool
// =============================================================================

param systemPoolConfig = {
  name: 'system'
  vmSize: 'Standard_D4s_v5'
  nodeCount: 2
  minCount: 2
  maxCount: 3
  zones: ['1', '2', '3']
  osDiskSizeGb: 128
  enableAutoScaling: true
}

// =============================================================================
// Standard (On-Demand) Node Pools - Fallback for spot failures
// =============================================================================

param standardPoolConfigs = [
  {
    name: 'stdfallback'
    vmSize: 'Standard_D4s_v5'
    minCount: 1
    maxCount: 2
    zones: ['1', '2', '3']
    osDiskSizeGb: 128
    enableAutoScaling: true
    labels: {
      'workload-tier': 'production'
      'priority': 'on-demand'
    }
  }
]

// =============================================================================
// Spot Node Pools - Diversified Strategy
// Each pool: 1 zone + 1 SKU family = maximum resilience
// =============================================================================

param spotPoolConfigs = [
  // Zone 1: D-series (general purpose, 4 vCPU)
  {
    name: 'spotd4z1'
    vmSize: 'Standard_D4s_v5'
    minCount: 0
    maxCount: 3
    zones: ['1']
    spotMaxPrice: -1
    evictionPolicy: 'Delete'
    priorityWeight: 10
    enableAutoScaling: true
    labels: {
      'spot-pool-id': '1'
      'vm-family': 'd-series'
      'zone': '1'
    }
  }
  // Zone 2: D-series (general purpose, 8 vCPU)
  {
    name: 'spotd8z2'
    vmSize: 'Standard_D8s_v5'
    minCount: 0
    maxCount: 3
    zones: ['2']
    spotMaxPrice: -1
    evictionPolicy: 'Delete'
    priorityWeight: 10
    enableAutoScaling: true
    labels: {
      'spot-pool-id': '2'
      'vm-family': 'd-series'
      'zone': '2'
    }
  }
  // Zone 3: E-series (memory optimized)
  {
    name: 'spote4z3'
    vmSize: 'Standard_E4s_v5'
    minCount: 0
    maxCount: 3
    zones: ['3']
    spotMaxPrice: -1
    evictionPolicy: 'Delete'
    priorityWeight: 10
    enableAutoScaling: true
    labels: {
      'spot-pool-id': '3'
      'vm-family': 'e-series'
      'zone': '3'
    }
  }
  // Zone 1: F-series (compute optimized) - different family, same zone
  {
    name: 'spotf8z1'
    vmSize: 'Standard_F8s_v2'
    minCount: 0
    maxCount: 3
    zones: ['1']
    spotMaxPrice: -1
    evictionPolicy: 'Delete'
    priorityWeight: 5  // Lower priority = backup option
    enableAutoScaling: true
    labels: {
      'spot-pool-id': '4'
      'vm-family': 'f-series'
      'zone': '1'
    }
  }
]

// =============================================================================
// Optional: Azure AD RBAC
// =============================================================================

param enableAzureRbac = true
param adminGroupObjectIds = [
  // Add your Azure AD group object IDs here
  // '12345678-1234-1234-1234-123456789abc'
]

// =============================================================================
// Optional: Monitoring
// =============================================================================

// Replace with your Log Analytics workspace ID if enabling monitoring
param logAnalyticsWorkspaceId = ''

// =============================================================================
// Tags
// =============================================================================

param tags = {
  environment: 'prod'
  location: 'australiaeast'
  'managed-by': 'bicep'
  project: 'aks-spot-optimization'
  'cost-center': 'platform'
  owner: 'devops-team'
}
