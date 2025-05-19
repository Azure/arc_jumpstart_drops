resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-07-01' = {
  name: 'JumpstartAKS'
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    disableLocalAccounts: false
    agentPoolProfiles: [
      {
        count: 3
        mode: 'System'
        name: 'systempool'
        vmSize: 'Standard_DS4_v2'
      }
      {
        name: 'gpupool'
        count: 1
        mode: 'User'
        vmSize: 'Standard_NC12s_v3'
        osDiskSizeGB: 128
        osType: 'Linux'
        maxPods: 110
      }
    ]
    dnsPrefix: '${toLower('JumpstartAKS')}-dns'
    enableRBAC: true
  }
}

output controlPlaneFQDN string = aksCluster.properties.fqdn
output kubeletIdentity string = aksCluster.properties.identityProfile.kubeletidentity.objectId
