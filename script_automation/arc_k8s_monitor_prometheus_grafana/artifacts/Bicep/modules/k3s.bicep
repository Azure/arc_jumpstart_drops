@description('The name of you Virtual Machine')
param vmName string = 'js-k3s-${namingGuid}'

@description('Username for the Virtual Machine')
param adminUsername string = 'jumpstartuser'

@description('RSA public key used for securing SSH access to ArcBox resources. This parameter is only needed when deploying the DataOps or DevOps flavors.')
@secure()
param sshRSAPublicKey string = ''

@description('The Ubuntu version for the VM. This will pick a fully patched image of this given Ubuntu version')
@allowed([
  '22_04-lts-gen2'
])
param ubuntuOSVersion string = '22_04-lts-gen2'

@description('Location for all resources.')
param azureLocation string = resourceGroup().location

@description('The size of the VM')
param vmSize string = 'Standard_B4ms'

@description('Resource Id of the subnet in the virtual network')
param subnetId string

@description('The base URL used for accessing artifacts and automation artifacts')
param templateBaseUrl string

@maxLength(5)
@description('Random GUID')
param namingGuid string

@description('Azure Monitor workspace ID')
param monitorWorkspaceId string

var publicIpAddressName = '${vmName}-pip'
var networkInterfaceName = '${vmName}-nic'
var osDiskType = 'Premium_LRS'
var diskSize = 32
var numberOfIPAddresses =  1 // The number of IP addresses to create

// Create multiple public IP addresses
resource publicIpAddresses 'Microsoft.Network/publicIpAddresses@2022-01-01' = [for i in range(1, numberOfIPAddresses): {
  name: '${publicIpAddressName}${i}'
  location: azureLocation
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
  sku: {
    name: 'Basic'
  }
}]

// Create multiple NIC IP configurations and assign the public IP to the IP configuration
resource networkInterface 'Microsoft.Network/networkInterfaces@2022-01-01' = {
  name: networkInterfaceName
  location: azureLocation
  properties: {
    ipConfigurations: [for i in range(1, numberOfIPAddresses): {
      name: 'ipconfig${i}'
      properties: {
        subnet: {
          id: subnetId
        }
        privateIPAllocationMethod: 'Dynamic'
        publicIPAddress: {
          id: publicIpAddresses[i-1].id
        }
        primary: i == 1 ? true : false
      }
    }]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2022-03-01' = {
  name: vmName
  location: azureLocation
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      osDisk: {
        name: '${vmName}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskType
        }
        diskSizeGB: diskSize
      }
      imageReference: {
        publisher: 'canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: ubuntuOSVersion
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshRSAPublicKey
            }
          ]
        }
      }
    }
  }
}

// Add role assignment for the VM: Owner role
resource vmRoleAssignment_Owner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vm.id, 'Microsoft.Authorization/roleAssignments', 'Owner')
  scope: resourceGroup()
  properties: {
    principalId: vm.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')
    principalType: 'ServicePrincipal'
  }
}

resource vmInstallscriptK3s 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = {
  parent: vm
  name: 'installscript_k3s'
  location: azureLocation
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      commandToExecute: 'bash k3sMonitoring.sh ${adminUsername} ${subscription().subscriptionId} ${vmName} ${azureLocation} ${templateBaseUrl} ${resourceGroup().name} ${monitorWorkspaceId}'
      fileUris: [
        '${templateBaseUrl}scripts/k3sMonitoring.sh'
      ]
    }
  }
  dependsOn: [
    vmRoleAssignment_Owner
  ]
}
