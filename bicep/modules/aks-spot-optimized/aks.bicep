// =============================================================================
// AKS Cluster Module
// Purpose: Create AKS cluster with system node pool and core configuration
// =============================================================================

@description('Location for the cluster')
param location string

@description('Name of the AKS cluster')
param clusterName string

@description('Kubernetes version')
param kubernetesVersion string

@description('Subnet resource ID for AKS nodes')
param vnetSubnetId string

@description('System node pool configuration')
param systemPoolConfig object

@description('Network profile configuration')
param networkProfile object

@description('Cluster autoscaler profile')
param autoscalerProfile object

@description('Enable Azure AD RBAC')
param enableAzureRbac bool

@description('Admin group object IDs')
param adminGroupObjectIds array

@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

@description('Tags')
param tags object

// =============================================================================
// AKS Cluster Resource
// =============================================================================

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: clusterName
    enableRBAC: true
    nodeResourceGroup: 'MC_${resourceGroup().name}_${clusterName}_${location}'

    // OIDC Issuer for workload identity
    oidcIssuerProfile: {
      enabled: true
    }

    // System Node Pool (Default)
    agentPoolProfiles: [
      {
        name: systemPoolConfig.name
        count: systemPoolConfig.enableAutoScaling ? null : systemPoolConfig.nodeCount
        minCount: systemPoolConfig.enableAutoScaling ? systemPoolConfig.minCount : null
        maxCount: systemPoolConfig.enableAutoScaling ? systemPoolConfig.maxCount : null
        vmSize: systemPoolConfig.vmSize
        osDiskSizeGB: systemPoolConfig.osDiskSizeGb
        osDiskType: contains(systemPoolConfig, 'osDiskType') ? systemPoolConfig.osDiskType : 'Managed'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        maxPods: contains(systemPoolConfig, 'maxPods') ? systemPoolConfig.maxPods : 30
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        enableAutoScaling: systemPoolConfig.enableAutoScaling
        availabilityZones: systemPoolConfig.zones
        vnetSubnetID: vnetSubnetId
        enableNodePublicIP: false
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
        upgradeSettings: {
          maxSurge: '25%'
        }
        nodeLabels: {
          'node-pool-type': 'system'
          'managed-by': 'bicep'
          'cost-optimization': 'spot-enabled'
        }
      }
    ]

    // Network Profile
    networkProfile: {
      networkPlugin: networkProfile.networkPlugin
      networkPolicy: networkProfile.networkPolicy
      dnsServiceIP: networkProfile.dnsServiceIP
      serviceCidr: networkProfile.serviceCidr
      loadBalancerSku: networkProfile.loadBalancerSku
      outboundType: networkProfile.outboundType
    }

    // Cluster Autoscaler Profile - Optimized for Spot
    autoScalerProfile: {
      'balance-similar-node-groups': autoscalerProfile.balanceSimilarNodeGroups
      expander: autoscalerProfile.expander
      'max-graceful-termination-sec': autoscalerProfile.maxGracefulTerminationSec
      'max-node-provision-time': autoscalerProfile.maxNodeProvisioningTime
      'ok-total-unready-count': autoscalerProfile.maxUnreadyNodes
      'max-total-unready-percentage': autoscalerProfile.maxUnreadyPercentage
      'new-pod-scale-up-delay': autoscalerProfile.newPodScaleUpDelay
      'scale-down-delay-after-add': autoscalerProfile.scaleDownDelayAfterAdd
      'scale-down-delay-after-delete': autoscalerProfile.scaleDownDelayAfterDelete
      'scale-down-delay-after-failure': autoscalerProfile.scaleDownDelayAfterFailure
      'scale-down-unneeded-time': autoscalerProfile.scaleDownUnneededTime
      'scale-down-unready-time': autoscalerProfile.scaleDownUnreadyTime
      'scale-down-utilization-threshold': autoscalerProfile.scaleDownUtilizationThreshold
      'scan-interval': autoscalerProfile.scanInterval
      'skip-nodes-with-local-storage': autoscalerProfile.skipNodesWithLocalStorage
      'skip-nodes-with-system-pods': autoscalerProfile.skipNodesWithSystemPods
    }

    // Azure AD RBAC
    aadProfile: enableAzureRbac ? {
      managed: true
      enableAzureRBAC: true
      adminGroupObjectIDs: adminGroupObjectIds
    } : null

    // Azure Monitor
    addonProfiles: !empty(logAnalyticsWorkspaceId) ? {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    } : {}
  }
}

// =============================================================================
// Outputs
// =============================================================================

output clusterResourceId string = aksCluster.id
output clusterName string = aksCluster.name
output clusterFqdn string = aksCluster.properties.fqdn
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
