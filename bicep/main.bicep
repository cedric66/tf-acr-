// =============================================================================
// AKS Spot-Optimized - Main Bicep Template
// Purpose: Deploy AKS cluster with cost-optimized spot node pool strategy
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// Parameters
// =============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of the AKS cluster')
param clusterName string

@description('Kubernetes version')
param kubernetesVersion string = '1.34'

@description('Existing subnet resource ID for AKS nodes')
param vnetSubnetId string

@description('System node pool configuration')
param systemPoolConfig object

@description('Standard (on-demand) node pool configurations')
param standardPoolConfigs array = []

@description('Spot node pool configurations')
param spotPoolConfigs array = []

@description('Network profile configuration')
param networkProfile object = {
  networkPlugin: 'azure'
  networkPolicy: 'azure'
  dnsServiceIP: '10.0.0.10'
  serviceCidr: '10.0.0.0/16'
  loadBalancerSku: 'standard'
  outboundType: 'loadBalancer'
}

@description('Cluster autoscaler profile - optimized for spot workloads')
param autoscalerProfile object = {
  balanceSimilarNodeGroups: 'true'
  expander: 'priority'
  maxGracefulTerminationSec: '600'
  maxNodeProvisioningTime: '15m'
  maxUnreadyNodes: '3'
  maxUnreadyPercentage: '45'
  newPodScaleUpDelay: '0s'
  scaleDownDelayAfterAdd: '10m'
  scaleDownDelayAfterDelete: '10s'
  scaleDownDelayAfterFailure: '3m'
  scaleDownUnneededTime: '10m'
  scaleDownUnreadyTime: '20m'
  scaleDownUtilizationThreshold: '0.5'
  scanInterval: '10s'
  skipNodesWithLocalStorage: 'false'
  skipNodesWithSystemPods: 'true'
}

@description('Enable Azure AD RBAC')
param enableAzureRbac bool = true

@description('Admin group object IDs for Azure AD RBAC')
param adminGroupObjectIds array = []

@description('Log Analytics workspace ID for monitoring')
param logAnalyticsWorkspaceId string = ''

@description('Tags for all resources')
param tags object = {}

// =============================================================================
// AKS Cluster
// =============================================================================

module aksCluster 'modules/aks-spot-optimized/aks.bicep' = {
  name: 'aks-${clusterName}'
  params: {
    location: location
    clusterName: clusterName
    kubernetesVersion: kubernetesVersion
    vnetSubnetId: vnetSubnetId
    systemPoolConfig: systemPoolConfig
    networkProfile: networkProfile
    autoscalerProfile: autoscalerProfile
    enableAzureRbac: enableAzureRbac
    adminGroupObjectIds: adminGroupObjectIds
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    tags: tags
  }
}

// =============================================================================
// Standard (On-Demand) Node Pools
// =============================================================================

module standardPools 'modules/aks-spot-optimized/node-pools.bicep' = [for (pool, i) in standardPoolConfigs: {
  name: 'nodepool-std-${pool.name}'
  params: {
    clusterName: clusterName
    poolConfig: pool
    poolType: 'standard'
    vnetSubnetId: vnetSubnetId
    tags: tags
  }
  dependsOn: [
    aksCluster
  ]
}]

// =============================================================================
// Spot Node Pools
// =============================================================================

module spotPools 'modules/aks-spot-optimized/node-pools.bicep' = [for (pool, i) in spotPoolConfigs: {
  name: 'nodepool-spot-${pool.name}'
  params: {
    clusterName: clusterName
    poolConfig: pool
    poolType: 'spot'
    vnetSubnetId: vnetSubnetId
    tags: tags
  }
  dependsOn: [
    aksCluster
  ]
}]

// =============================================================================
// Outputs
// =============================================================================

@description('AKS cluster resource ID')
output clusterResourceId string = aksCluster.outputs.clusterResourceId

@description('AKS cluster name')
output clusterNameOutput string = aksCluster.outputs.clusterName

@description('AKS cluster FQDN')
output clusterFqdn string = aksCluster.outputs.clusterFqdn

@description('Kubelet identity object ID (for RBAC assignments)')
output kubeletIdentityObjectId string = aksCluster.outputs.kubeletIdentityObjectId

@description('OIDC issuer URL')
output oidcIssuerUrl string = aksCluster.outputs.oidcIssuerUrl
