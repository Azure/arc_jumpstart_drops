@description('Location for all resources')
param location string = resourceGroup().location

@maxLength(5)
@description('Random GUID')
param namingGuid string = toLower(substring(newGuid(), 0, 5))

@description('Target GitHub account')
param githubAccount string = 'azure'

@description('Target GitHub branch')
param githubBranch string = 'main'

@description('Choice to deploy Bastion to connect to the client VM')
param deployBastion bool = false

@description('Name of the Cloud VNet')
param virtualNetworkNameCloud string = 'js-vnet-prod'

@description('Name of the Staging AKS subnet in the cloud virtual network')
param subnetNameCloudK3s string = 'js-subnet-k3s'

@description('Configure all linux machines with the SSH RSA public key string. Your key should include three parts, for example \'ssh-rsa AAAAB...snip...UcyupgH azureuser@linuxvm\'')
param sshRSAPublicKey string

@description('The name of the Azure Arc K3s cluster')
param k3sArcDataClusterName string = 'js-k3s-${namingGuid}'

var templateBaseUrl = 'https://raw.githubusercontent.com/${githubAccount}/arc_jumpstart_drops/${githubBranch}/script_automation/arc_k8s_monitor_prometheus_grafana/artifacts/Bicep/'

module mgmtArtifacts 'modules/mgmtArtifacts.bicep' = {
  name: 'mgmtArtifacts'
  params: {
    virtualNetworkNameCloud: virtualNetworkNameCloud
    subnetNameCloudK3s: subnetNameCloudK3s
    deployBastion: deployBastion
    location: location
    namingGuid: namingGuid
  }
}
module k3sDeployment 'modules/k3s.bicep' = {
  name: 'ubuntuRancherK3s2Deployment'
  params: {
    sshRSAPublicKey: sshRSAPublicKey
    templateBaseUrl: templateBaseUrl
    subnetId: mgmtArtifacts.outputs.k3sSubnetId
    azureLocation: location
    vmName : k3sArcDataClusterName
    namingGuid: namingGuid
    monitorWorkspaceId: mgmtArtifacts.outputs.monitorWorkspaceId
  }
}
