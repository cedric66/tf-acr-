// =============================================================================
// Node Pools Module
// Purpose: Create standard or spot node pools for AKS cluster
// =============================================================================

@description('Name of the AKS cluster to add node pool to')
param clusterName string

@description('Node pool configuration')
param poolConfig object

@description('Type of node pool: standard or spot')
@allowed(['standard', 'spot'])
param poolType string

@description('Subnet resource ID')
param vnetSubnetId string

@description('Tags')
param tags object

// =============================================================================
// Reference Existing Cluster
// =============================================================================

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-05-01' existing = {
  name: clusterName
}

// =============================================================================
// Node Pool Resource
// =============================================================================

resource nodePool 'Microsoft.ContainerService/managedClusters/agentPools@2024-05-01' = {
  parent: aksCluster
  name: poolConfig.name
  properties: {
    // Common properties
    count: poolConfig.enableAutoScaling ? null : poolConfig.minCount
    minCount: poolConfig.enableAutoScaling ? poolConfig.minCount : null
    maxCount: poolConfig.enableAutoScaling ? poolConfig.maxCount : null
    vmSize: poolConfig.vmSize
    osDiskSizeGB: contains(poolConfig, 'osDiskSizeGb') ? poolConfig.osDiskSizeGb : 128
    osDiskType: contains(poolConfig, 'osDiskType') ? poolConfig.osDiskType : 'Managed'
    osType: 'Linux'
    osSKU: 'Ubuntu'
    maxPods: contains(poolConfig, 'maxPods') ? poolConfig.maxPods : 30
    type: 'VirtualMachineScaleSets'
    mode: 'User'
    enableAutoScaling: poolConfig.enableAutoScaling
    availabilityZones: poolConfig.zones
    vnetSubnetID: vnetSubnetId
    enableNodePublicIP: false
    scaleDownMode: 'Delete'

    // Spot-specific properties
    scaleSetPriority: poolType == 'spot' ? 'Spot' : 'Regular'
    scaleSetEvictionPolicy: poolType == 'spot' ? poolConfig.evictionPolicy : null
    spotMaxPrice: poolType == 'spot' ? poolConfig.spotMaxPrice : null

    // Node taints - spot pools get spot taint
    nodeTaints: poolType == 'spot' 
      ? concat(['kubernetes.azure.com/scalesetpriority=spot:NoSchedule'], contains(poolConfig, 'taints') ? poolConfig.taints : [])
      : contains(poolConfig, 'taints') ? poolConfig.taints : []

    // Node labels
    nodeLabels: union(
      contains(poolConfig, 'labels') ? poolConfig.labels : {}
      {
        'node-pool-type': 'user'
        'workload-type': poolType
        'priority': poolType == 'spot' ? 'spot' : 'on-demand'
        'managed-by': 'bicep'
        'cost-optimization': 'spot-enabled'
      }
    )

    // Upgrade settings differ by pool type
    // Standard pools use maxUnavailable (no surge IPs)
    // Spot pools cannot use upgrade settings
    upgradeSettings: poolType == 'standard' ? {
      maxSurge: ''
      maxUnavailable: '1'
    } : null

    tags: union(tags, {
      'node-pool-type': poolType
      'priority': poolType == 'spot' ? 'spot' : 'on-demand'
      'vm-size': poolConfig.vmSize
    })
  }
}

// =============================================================================
// Outputs
// =============================================================================

output nodePoolName string = nodePool.name
output nodePoolId string = nodePool.id
