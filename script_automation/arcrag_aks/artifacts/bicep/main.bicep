// Bicep template to deploy AKS cluster and premium storage account with NFS share

param aksName string = 'edgerag-cluster'
param aksLocation string = resourceGroup().location
param aksNodeCount int =  6
param aksNodeVMSize string = 'Standard_D8s_v3'
param adminUsername string = 'arcuser'
param sshPublicKey string
var storageAccountName = toLower('nfsjs${uniqueString(resourceGroup().id, deployment().name)}')
param storageAccountLocation string = resourceGroup().location
// DNS suffix for storage account file endpoints (override for sovereign clouds)
param storageDnsSuffix string = 'file.${environment().suffixes.storage}'

// aksVnet already declared above

resource aks 'Microsoft.ContainerService/managedClusters@2025-05-01' = {
  name: aksName
  location: aksLocation
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: aksName
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: aksNodeCount
        vmSize: aksNodeVMSize
        osType: 'Linux'
        mode: 'System'
  vnetSubnetID: resourceId('Microsoft.Network/virtualNetworks/subnets', aksVnet.name, 'aks-subnet')
      }
    ]
    linuxProfile: {
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    }

    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: '10.81.0.0/16'
      dnsServiceIP: '10.81.0.10'
    }
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: storageAccountLocation
  sku: {
    name: 'Premium_LRS'
  }
  kind: 'FileStorage'
  properties: {
  supportsHttpsTrafficOnly: false
  allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: true
    isHnsEnabled: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
        virtualNetworkRules: [
          {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', aksVnet.name, 'aks-subnet')
          }
        ]
      ipRules: []
    }
  }
}


resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource nfsShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileServices
  name: 'nfs-share'
  properties: {
    enabledProtocols: 'NFS'
    shareQuota: 100
  }
}

resource aksVnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: '${aksName}-vnet'
  location: aksLocation
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'aks-subnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
    ]
  }
}

output aksClusterId string = aks.id
output storageAccountName string = storageAccount.name
output nfsShareMountPath string = '${storageAccount.name}.${storageDnsSuffix}:/${storageAccount.name}/${nfsShare.name}'
