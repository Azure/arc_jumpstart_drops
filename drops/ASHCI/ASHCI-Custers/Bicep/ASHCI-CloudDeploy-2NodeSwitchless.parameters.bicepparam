using '../Bicep/ASHCI-CloudDeploy-Template.bicep'

param deploymentMode = 'Validate'

param keyVaultName = 'hci-cluster-hcikv'

param softDeleteRetentionDays = 30

param diagnosticStorageAccountName = 'hciclusterdiag'

param logsRetentionInDays = 30

param storageAccountType = 'Standard_LRS'

param secretsLocation = 'https://hci-cluster-hcikv.vault.azure.net/'

param ClusterWitnessStorageAccountName = 'hciclustersa'

param clusterName = 'HCI-HCICluster'

param location = 'EastUS'

/*
Parameter metadata is not supported in Bicep Parameters files

Following metadata was not decompiled:
{
  "description": "Provide the Tenant ID of the Azure Subscription."
}
*/
param tenantId = ''

/*
Parameter metadata is not supported in Bicep Parameters files

Following metadata was not decompiled:
{
  "description": "Do not change this Value."
}
*/
param localAdminSecretName = 'LocalAdminCredential'

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
  "description": "Do not change this Value."
}
*/
param domainAdminSecretName = 'AzureStackLCMUserCredential'

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
  "description": "Do not change this Value."
}
*/
param arbDeploymentSpnName = 'DefaultARBApplication'

param arbDeploymentSpnValue = 'MTg2NzU1OWQtYmIyMS00ZGY2LTg0OTEtNTdmMmY3OGEwYjQ4OjFJWDhRfmlFYlduYkdma0tsTHd5eGpETFFhXzhmNUV0RXdIZkNidkg='

/*
Parameter metadata is not supported in Bicep Parameters files

Following metadata was not decompiled:
{
  "description": "Do not change this Value."
}
*/
param storageWitnessName = 'WitnessStorageKey'

param storageWitnessValue = 'YUMrbzhaUjJMbGdQbEduMGlWd3FxNnN6aG5kWE1wdHltTFRJM0lqV3dnUGtaRk9CK1VSNGxQRFNyd1pwYi90T25YS3QwRlBzaUpBUytBU3RRak5oOHc9PQ=='

param apiVersion = '2023-08-01-preview'

/*
Parameter metadata is not supported in Bicep Parameters files

Following metadata was not decompiled:
{
  "description": "Provide the Arc-Enabled Machine Resource ID of all the ASHCI nodes"
}
*/
param arcNodeResourceIds = [
  '/subscriptions/03d13178-3e31-454d-9bdd-9e93bc53828a/resourceGroups/Orlando/providers/Microsoft.HybridCompute/machines/ORL-Node1'
  '/subscriptions/03d13178-3e31-454d-9bdd-9e93bc53828a/resourceGroups/Orlando/providers/Microsoft.HybridCompute/machines/ORL-Node2'
]

param domainFqdn = 'domain.com'

param namingPrefix = 'HCI'

/*
Parameter metadata is not supported in Bicep Parameters files

Following metadata was not decompiled:
{
  "description": "Provide OU to place AHSCI Cluster and Node Computer Objects"
}
*/
param adouPath = 'OU=HCI,OU=Hypervisors,OU=Servers,OU=Computers,OU=TailwindTraders,DC=tailwindtraders,DC=com'

param securityLevel = 'Recommended'

param driftControlEnforced = true

param credentialGuardEnforced = true

param smbSigningEnforced = true

param smbClusterEncryption = false

param bitlockerBootVolume = true

param bitlockerDataVolumes = true

param wdacEnforced = true

param streamingDataClient = true

param euLocation = false

param episodicDataUpload = true

param configurationMode = 'Express'

param subnetMask = '255.255.255.0'

param defaultGateway = '10.10.0.1'

param startingIPAddress = '10.10.0.20'

param endingIPAddress = '10.10.0.30'

param dnsServers = [
  '10.10.1.8'
  '10.10.1.9'
]

param physicalNodesSettings = [
  {
    name: 'HCI-Node1'
    ipv4Address: '10.10.0.11'
  }
  {
    name: 'HCI-Node2'
    ipv4Address: '10.10.0.13'
  }
]

param networkingType = 'switchlessMultiServerDeployment'

param storageConnectivitySwitchless = true

param networkingPattern = 'ConvergedManagmentCompute'

param intentList = [
  {
    name: 'HCI'
    trafficType: [
      'Management'
      'Compute'
    ]
    adapter: [
      'MGMT-A'
      'MGMT-B'
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
    overrideAdapterProperty: true
    adapterPropertyOverrides: {
      jumboPacket: '9014'
      networkDirect: 'Disabled'
      networkDirectTechnology: 'RoCEv2'
    }
  }
  {
    name: 'Storage'
    trafficType: [
      'Storage'
    ]
    adapter: [
      'SMB-A'
      'SMB-B'
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
    overrideAdapterProperty: true
    adapterPropertyOverrides: {
      jumboPacket: '9014'
      networkDirect: 'Enabled'
      networkDirectTechnology: 'iWARP'
    }
  }
]

param storageNetworkList = [
  {
    name: 'StorageNetwork1'
    networkAdapterName: 'SMB-A'
    vlanId: '711'
  }
  {
    name: 'StorageNetwork2'
    networkAdapterName: 'SMB-B'
    vlanId: '712'
  }
]

param customLocation = 'HCI'
