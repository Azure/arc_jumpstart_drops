using '../Bicep/ASHCI-CloudDeploy-Template.bicep'

param apiVersion = '2024-02-15-preview'

/*
Parameter metadata is not supported in Bicep Parameters files

Following metadata was not decompiled:
{
  "description": "Provide the Arc-Enabled Machine Resource ID of all the ASHCI nodes"
}
*/
param arcNodeResourceIds = [
  ''
  ''
]

/*
Parameter metadata is not supported in Bicep Parameters files

Following metadata was not decompiled:
{
  "description": "This should be base64 value in UserName:Password format."
}
*/
param localAdminSecretValue = ''

/*
Parameter metadata is not supported in Bicep Parameters files

Following metadata was not decompiled:
{
  "description": "This should be base64 value in UserName:Password format."
}
*/
param domainAdminSecretValue = ''

/*
Parameter metadata is not supported in Bicep Parameters files

Following metadata was not decompiled:
{
  "description": "This should be base64 value in ApplicationID:Password format."
}
*/
param arbDeploymentSpnValue = ''

/*
Parameter metadata is not supported in Bicep Parameters files

Following metadata was not decompiled:
{
  "description": "This should be base64 value in StorageAccountKey format."
}
*/
param storageWitnessValue = ''

param domainFqdn = 'contoso.com'

param namingPrefix = 'HCI'

param clusterName = 'ThreeNCluster'

param keyVaultName = 'ThreeNClusterKeyVault'

param softDeleteRetentionDays = 30

param diagnosticStorageAccountName = 'autoipoffdiagsa'

param logsRetentionInDays = 30

param storageAccountType = 'Standard_LRS'

param adouPath = 'OU=HCI,DC=contoso,DC=com'

param subnetMask = '255.255.255.0'

param defaultGateway = '192.168.44.1'

param startingIPAddress = '192.168.44.220'

param endingIPAddress = '192.168.44.230'

param ClusterWitnessStorageAccountName = 'autoipoffsa'

param dnsServers = [
  '192.168.1.254'
]

param enableStorageAutoIp = false

param storageConnectivitySwitchless = true

param physicalNodesSettings = [
  {
    name: 'Node1'
    ipv4Address: '192.168.44.201'
  }
  {
    name: 'Node2'
    ipv4Address: '192.168.44.202'
  }
  {
    name: 'Node3'
    ipv4Address: '192.168.44.203'
  }
]

param networkingPattern = 'convergedManagementCompute'

param intentList = [
  {
    name: 'Compute_Management'
    trafficType: [
      'Management'
      'Compute'
    ]
    adapter: [
      'NIC1'
      'NIC2'
    ]
    overrideVirtualSwitchConfiguration: false
    virtualSwitchConfigurationOverrides: {
      enableIov: ''
      loadBalancingAlgorithm: ''
    }
    overrideQosPolicy: false
    qosPolicyOverrides: {
      priorityValue8021Action_Cluster: '7'
      priorityValue8021Action_SMB: '3'
      bandwidthPercentage_SMB: '50'
    }
    overrideAdapterProperty: false
    adapterPropertyOverrides: {
      jumboPacket: '9014'
      networkDirect: 'Enabled'
      networkDirectTechnology: 'RoCEv2'
    }
  }
  {
    name: 'Storage'
    trafficType: [
      'Storage'
    ]
    adapter: [
      'SMB1'
      'SMB2'
      'SMB3'
      'SMB4'
    ]
    overrideVirtualSwitchConfiguration: false
    virtualSwitchConfigurationOverrides: {
      enableIov: ''
      loadBalancingAlgorithm: ''
    }
    overrideQosPolicy: false
    qosPolicyOverrides: {
      priorityValue8021Action_Cluster: '7'
      priorityValue8021Action_SMB: '3'
      bandwidthPercentage_SMB: '50'
    }
    overrideAdapterProperty: false
    adapterPropertyOverrides: {
      jumboPacket: '9014'
      networkDirect: 'Enabled'
      networkDirectTechnology: 'RoCEv2'
    }
  }
]

param storageNetworkList = [
  {
    name: 'StorageNetwork1'
    networkAdapterName: 'SMB1'
    vlanId: '711'
    storageAdapterIPInfo: [
      {
        physicalNode: 'Node1'
        ipv4Address: '10.0.1.1'
        subnetMask: '255.255.255.0'
      }
      {
        physicalNode: 'Node2'
        ipv4Address: '10.0.1.2'
        subnetMask: '255.255.255.0'
      }
      {
        physicalNode: 'Node3'
        ipv4Address: '10.0.5.3'
        subnetMask: '255.255.255.0'
      }
    ]
  }
  {
    name: 'StorageNetwork2'
    networkAdapterName: 'SMB2'
    vlanId: '711'
    storageAdapterIPInfo: [
      {
        physicalNode: 'Node1'
        ipv4Address: '10.0.2.1'
        subnetMask: '255.255.255.0'
      }
      {
        physicalNode: 'Node2'
        ipv4Address: '10.0.2.2'
        subnetMask: '255.255.255.0'
      }
      {
        physicalNode: 'Node3'
        ipv4Address: '10.0.4.3'
        subnetMask: '255.255.255.0'
      }
    ]
  }
  {
    name: 'StorageNetwork3'
    networkAdapterName: 'SMB3'
    vlanId: '711'
    storageAdapterIPInfo: [
      {
        physicalNode: 'Node1'
        ipv4Address: '10.0.5.1'
        subnetMask: '255.255.255.0'
      }
      {
        physicalNode: 'Node2'
        ipv4Address: '10.0.3.2'
        subnetMask: '255.255.255.0'
      }
      {
        physicalNode: 'Node3'
        ipv4Address: '10.0.3.3'
        subnetMask: '255.255.255.0'
      }
    ]
  }
  {
    name: 'StorageNetwork4'
    networkAdapterName: 'SMB4'
    vlanId: '711'
    storageAdapterIPInfo: [
      {
        physicalNode: 'Node1'
        ipv4Address: '10.0.4.2'
        subnetMask: '255.255.255.0'
      }
      {
        physicalNode: 'Node2'
        ipv4Address: '10.0.6.1'
        subnetMask: '255.255.255.0'
      }
      {
        physicalNode: 'Node3'
        ipv4Address: '10.0.6.3'
        subnetMask: '255.255.255.0'
      }
    ]
  }
]

param secretsLocation = 'https://ThreeNClusterKeyVault.vault.azure.net'

param networkingType = 'switchlessMultiServerDeployment'

param customLocation = 'MasMaria'

param deploymentMode = 'Validate'
