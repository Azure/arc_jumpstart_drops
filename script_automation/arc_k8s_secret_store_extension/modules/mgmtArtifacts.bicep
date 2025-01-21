@description('Name of the Cloud VNet')
param virtualNetworkNameCloud string

@description('Name of the K3s subnet in the cloud virtual network')
param subnetNameCloudK3s string

@description('Azure Region to deploy the Azure resources')
param location string = resourceGroup().location

@description('Resource tag for Jumpstart Drops')
param resourceTags object = {
  Project: 'Jumpstart_Drops'
}

@description('Choice to deploy Bastion to connect to the client VM')
param deployBastion bool = false

@description('Name of the prod Network Security Group')
param networkSecurityGroupNameCloud string = 'js-nsg-prod'

@description('Name of the Bastion Network Security Group')
param bastionNetworkSecurityGroupName string = 'js-nsg-bastion'

@description('Azure Key Vault tenant ID')
param tenantId string = subscription().tenantId

@description('Azure Key Vault SKU')
param akvSku string = 'standard'

@maxLength(5)
@description('Random GUID')
param namingGuid string

@description('The name of the user assigned identity')
param userAssignedIdentityName string = 'js-uai-sse'

var addressPrefixCloud = '10.16.0.0/16'
var subnetAddressPrefixK3s = '10.16.80.0/21'
var bastionSubnetIpPrefix = '10.16.3.64/26'
var bastionSubnetName = 'AzureBastionSubnet'
var bastionSubnetRef = '${cloudVirtualNetwork.id}/subnets/${bastionSubnetName}'
var bastionName = 'js-bastion'
var bastionPublicIpAddressName = '${bastionName}-pip'
var keyVaultName = 'js-kv-${namingGuid}'

var bastionSubnet = [
  {
    name: 'AzureBastionSubnet'
    properties: {
      addressPrefix: bastionSubnetIpPrefix
      networkSecurityGroup: {
        id: bastionNetworkSecurityGroup.id
      }
    }
  }
]
var cloudK3sSubnet = [
  {
    name: subnetNameCloudK3s
    properties: {
      addressPrefix: subnetAddressPrefixK3s
      privateEndpointNetworkPolicies: 'Enabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      networkSecurityGroup: {
        id: networkSecurityGroupCloud.id
      }
    }
  }
]

resource cloudVirtualNetwork 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: virtualNetworkNameCloud
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefixCloud
      ]
    }
    subnets: (deployBastion == false)
      ? cloudK3sSubnet
      : union(cloudK3sSubnet, bastionSubnet)
  }
}

resource publicIpAddress 'Microsoft.Network/publicIPAddresses@2023-02-01' = if (deployBastion == true) {
  name: bastionPublicIpAddressName
  location: location
  tags: resourceTags
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
  sku: {
    name: 'Standard'
  }
}

resource networkSecurityGroupCloud 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: networkSecurityGroupNameCloud
  location: location
  tags: resourceTags
  properties: {
    securityRules: []
  }
}

resource bastionNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-02-01' = if (deployBastion == true) {
  name: bastionNetworkSecurityGroupName
  location: location
  tags: resourceTags
  properties: {
    securityRules: [
      {
        name: 'bastion_allow_https_inbound'
        properties: {
          priority: 1010
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'bastion_allow_gateway_manager_inbound'
        properties: {
          priority: 1011
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'bastion_allow_load_balancer_inbound'
        properties: {
          priority: 1012
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'bastion_allow_host_comms'
        properties: {
          priority: 1013
          protocol: '*'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
        }
      }
      {
        name: 'bastion_allow_ssh_rdp_outbound'
        properties: {
          priority: 1014
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '22'
            '3389'
          ]
        }
      }
      {
        name: 'bastion_allow_azure_cloud_outbound'
        properties: {
          priority: 1015
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
      {
        name: 'bastion_allow_bastion_comms'
        properties: {
          priority: 1016
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
        }
      }
      {
        name: 'bastion_allow_get_session_info'
        properties: {
          priority: 1017
          protocol: '*'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRanges: [
            '80'
            '443'
          ]
        }
      }
    ]
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2023-02-01' = if (deployBastion == true) {
  name: bastionName
  location: location
  tags: resourceTags
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          publicIPAddress: {
            id: publicIpAddress.id
          }
          subnet: {
            id: bastionSubnetRef
          }
        }
      }
    ]
  }
}

resource akv 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: akvSku
      family: 'A'
    }
    enableRbacAuthorization: true
    enableSoftDelete: false
    tenantId: tenantId
  }
}

// Create User Assigned Identity
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  location: location
  name: userAssignedIdentityName
}

// Add role assignment for the UAI: Key Vault Reader
resource userAssignedIdentity_KVReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(userAssignedIdentity.id, 'Microsoft.Authorization/roleAssignments', 'Key Vault Reader')
  scope: resourceGroup()
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '21090545-7ca7-4776-b22c-e363652d74d2')
    principalType: 'ServicePrincipal'
  }
}

// Add role assignment for the UAI: Key Vault Secrets User
resource userAssignedIdentity_KVSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(userAssignedIdentity.id, 'Microsoft.Authorization/roleAssignments', 'Key Vault Secrets User')
  scope: resourceGroup()
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalType: 'ServicePrincipal'
  }
}

output vnetId string = cloudVirtualNetwork.id
output k3sSubnetId string = cloudVirtualNetwork.properties.subnets[0].id
output virtualNetworkNameCloud string = cloudVirtualNetwork.name
output keyVaultName string = keyVaultName
output userAssignedIdentityName string = userAssignedIdentityName
