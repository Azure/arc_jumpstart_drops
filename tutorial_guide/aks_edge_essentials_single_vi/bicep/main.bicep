@description('Location for all resources')
param location string = resourceGroup().location

@description('Username for Windows account')
param windowsAdminUsername string

@description('Password for Windows account. Password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. The value must be between 12 and 123 characters long')
@minLength(12)
@maxLength(123)
@secure()
param windowsAdminPassword string

@description('Name for Storage Account')
param storageAccountName string

@description('Name for Video Indexer')
param videoIndexerAccountName string = 'videoIndexer'

@description('Target GitHub account')
param githubAccount string = 'microsoft'

@description('Target GitHub branch')
param githubBranch string = 'main'

@description('Choice to deploy Bastion to connect to the client VM')
param deployBastion bool = false

@description('Name of the Cloud VNet')
param virtualNetworkNameCloud string = 'VNet-Prod'

@description('Name of the subnet in the cloud virtual network')
param subnetName string = 'Subnet-VM'

@description('Override default RDP port using this parameter. Default is 3389. No changes will be made to the client VM.')
param rdpPort string = '3389'

var templateBaseUrl = 'https://raw.githubusercontent.com/${githubAccount}/azure_arc/${githubBranch}/azure_arc_k8s_jumpstart/aks_hybrid/aks_edge_essentials_single_vi/'

module videoIndexer 'videoIndexer.bicep' = {
  name: 'videoIndexerDeployment'
  params: {
    storageAccountName: storageAccountName
    videoIndexerAccountName: videoIndexerAccountName
    location: location
  }
}

module networkDeployment 'network.bicep' = {
  name: 'networkDeployment'
  params: {
    virtualNetworkNameCloud: virtualNetworkNameCloud
    subnetName: subnetName
    deployBastion: deployBastion
    location: location
  }
}

module clientVmDeployment 'clientVm.bicep' = {
  name: 'clientVmDeployment'
  params: {
    windowsAdminUsername: windowsAdminUsername
    windowsAdminPassword: windowsAdminPassword
    videoIndexerAccountName: videoIndexer.outputs.videoIndexerAccountName
    videoIndexerAccountId: videoIndexer.outputs.videoIndexerPrincipalId
    templateBaseUrl: templateBaseUrl
    deployBastion: deployBastion

    location: location
    subnetId: networkDeployment.outputs.subnetId

    rdpPort: rdpPort

  }
}

