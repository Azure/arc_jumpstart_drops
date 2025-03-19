Start-Transcript -Path C:\Temp\LogonScript.log

Set-ExecutionPolicy Bypass -Scope Process -Force

# Parameters
$schemaVersionAksEdgeConfig = "1.13"
$versionAksEdgeConfig = "1.0"
$guid = ([System.Guid]::NewGuid()).ToString().subString(0,5).ToLower()
$clusterName = "$Env:resourceGroup-$guid"

# Verify EdgeEssentails features are installed
Install-AksEdgeHostFeatures

########################################################################
# Connect to Azure
########################################################################

Write-Host "Connecting to Azure..."

az login --identity

# Install Azure module if not already installed
if (-not (Get-Command -Name Get-AzContext)) {
    Write-Host "Installing Azure module..."
    Install-Module -Name Az -AllowClobber -Scope CurrentUser -ErrorAction Stop
}

# If not signed in, run the Connect-AzAccount cmdlet
if (-not (Get-AzContext)) {
    Write-Host "Logging in to Azure..."
    If (-not (Connect-AzAccount -SubscriptionId $env:AZURE_SUBSCRIPTION_ID -ErrorAction Stop)){
        Throw "Unable to login to Azure. Please check your credentials and try again."
    }
}

# Write-Host "Getting Azure Tenant Id..."
$tenantId = (Get-AzSubscription -SubscriptionId $env:AZURE_SUBSCRIPTION_ID).TenantId

# Write-Host "Setting Azure context..."
$context = Set-AzContext -SubscriptionId $env:AZURE_SUBSCRIPTION_ID -Tenant $tenantId -ErrorAction Stop

# Write-Host "Setting az subscription..."
$azLogin = az account set --subscription $env:AZURE_SUBSCRIPTION_ID

# Configure AKS disk
$storagePoolName = "AKS"
$diskName = "AKSData"
$disks = Get-Disk | Where-Object partitionStyle -eq "raw" | Get-PhysicalDisk
$storageName = Get-StorageSubsystem | Select-Object -expand FriendlyName
New-StoragePool -FriendlyName $storagePoolName -StorageSubSystemFriendlyName $storageName -PhysicalDisks $disks
New-VirtualDisk -StoragePoolFriendlyName $storagePoolName -FriendlyName $diskName -Size (500GB) -ResiliencySettingName Simple
Get-VirtualDisk -FriendlyName $diskName | Get-Disk | Initialize-Disk -Passthru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -NewFileSystemLabel $diskName

# Install AKS EE
$letter = Get-Volume | Where-Object FileSystemLabel -eq $diskName
$installPath = "$($letter.DriveLetter):\AKSEdge"
New-Item -Path $installPath -ItemType Directory
$aksEEk3sUrl = 'https://aka.ms/aks-edge/k3s-msi'
$tempDir = "C:\Temp"
$ProgressPreference = "SilentlyContinue"
Invoke-WebRequest $aksEEk3sUrl -OutFile $tempDir\AKSEEK3s.msi
msiexec.exe /i $tempDir\AKSEEK3s.msi INSTALLDIR=$installPath /q /passive
Start-Sleep 45

Import-Module AksEdge
Get-Command -Module AKSEdge | Format-Table Name, Version

# Here string for the json content
$aksedgeConfig = @"
{
    "SchemaVersion": "$schemaVersionAksEdgeConfig",
    "Version": "$versionAksEdgeConfig",
    "DeploymentType": "SingleMachineCluster",
    "Init": {
        "ServiceIPRangeSize": 30
    },
    "Network": {
        "NetworkPlugin": "$networkplugin",
        "InternetDisabled": false
    },
    "User": {
        "AcceptEula": true,
        "AcceptOptionalTelemetry": true
    },
    "Arc": {
        "ClusterName": "$clusterName",
        "Location": "${env:location}",
        "ResourceGroupName": "${env:resourceGroup}",
        "SubscriptionId": "${env:subscriptionId}",
        "TenantId": "${env:tenantId}"
    },
    "Machines": [
        {
            "LinuxNode": {
                "CpuCount": 12,
                "MemoryInMB": 50000,
                "DataSizeInGB": 300
            }
        }
    ]
}
"@

Set-Content -Path $tempDir\aksedge-config.json -Value $aksedgeConfig -Force

New-AksEdgeDeployment -JsonConfigFilePath $tempDir\aksedge-config.json

Write-Host "`n"
Write-Host "Checking kubernetes nodes"
Write-Host "`n"
kubectl get nodes -o wide
Write-Host "`n"

# az version
az -v

# login
az login --identity

# Installing Azure CLI extensions
az config set extension.use_dynamic_install=yes_without_prompt
Write-Host "`n"
Write-Host "Installing Azure CLI extensions"
# az extension add --name connectedk8s --version 1.3.17
az extension add --name k8s-extension
Write-Host "`n"

# Registering Azure Arc providers
Write-Host "Registering Azure Arc providers, hold tight..."
Write-Host "`n"
az provider register --namespace Microsoft.Kubernetes --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait
az provider register --namespace Microsoft.HybridCompute --wait
az provider register --namespace Microsoft.GuestConfiguration --wait
az provider register --namespace Microsoft.HybridConnectivity --wait
az provider register --namespace Microsoft.ExtendedLocation --wait

az provider show --namespace Microsoft.Kubernetes -o table
Write-Host "`n"
az provider show --namespace Microsoft.KubernetesConfiguration -o table
Write-Host "`n"
az provider show --namespace Microsoft.HybridCompute -o table
Write-Host "`n"
az provider show --namespace Microsoft.GuestConfiguration -o table
Write-Host "`n"
az provider show --namespace Microsoft.HybridConnectivity -o table
Write-Host "`n"
az provider show --namespace Microsoft.ExtendedLocation -o table
Write-Host "`n"

# Onboarding the cluster to Azure Arc
Write-Host "Onboarding the AKS Edge Essentials cluster to Azure Arc..."
Write-Host "`n"

$kubectlMonShell = Start-Process -PassThru PowerShell { for (0 -lt 1) { kubectl get pod -A; Start-Sleep -Seconds 5; Clear-Host } }

# Connect Arc-enabled kubernetes
# Connect-AksEdgeArc -JsonConfigFilePath $tempDir\aksedge-config.json
cp c:\ProgramData\chocolatey\bin\kubectl.exe ~\.azure\kubectl-client\
az connectedk8s connect -n $clusterName -l $env:location -g $Env:resourceGroup --subscription $env:subscriptionId


#####################################################################
### Install ingress-nginx
#####################################################################
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
Start-Sleep -Seconds 5
helm install ingress-nginx ingress-nginx/ingress-nginx

#####################################################################
### ACSA setup for RWX-capable storage class
#####################################################################
Write-Host "Installing Local Path Provisioner"
kubectl apply -f https://raw.githubusercontent.com/Azure/AKS-Edge/main/samples/storage/local-path-provisioner/local-path-storage.yaml

Write-Host "Increasing max users in EdgeEssentails"
Invoke-AksEdgeNodeCommand -NodeType "Linux" -Command "echo 'fs.inotify.max_user_instances = 1024' | sudo tee -a /etc/sysctl.conf && sudo sysctl -p"

Write-Host "Installing AIO Platform for Certificate Management"
az k8s-extension create --cluster-name $clusterName `
                        --name $clusterName"-certmgr" `
                        --resource-group $Env:resourceGroup `
                        --cluster-type connectedClusters `
                        --extension-type microsoft.iotoperations.platform `
                        --scope cluster `
                        --release-namespace cert-manager

Write-Host "Installing Azure Container Storage enabled by Azure Arc extension into AKS EE cluster."
az k8s-extension create --name azure-arc-containerstorage `
                        --extension-type microsoft.arc.containerstorage `
                        --scope cluster `
                        --cluster-name $clusterName `
                        --resource-group $Env:resourceGroup `
                        --cluster-type connectedClusters `
                        --config feature.diskStorageClass="default,local-path" `
                        --config edgeStorageConfiguration.create=true



#####################################################################
### Video Indexer setup
#####################################################################
#$viApiVersion="2024-09-23-preview" 
#$viApiVersion="2023-06-02-preview"
$viApiVersion="2025-03-01"
$extensionName="video-indexer"
#$version="1.0.41" # switch to blank
$version="1.1.30"
$namespace="video-indexer"
$releaseTrain="release" # switch to release
$storageClass="unbacked-sc"
$enable_gpu=false

#Write-Host "Create Cognitive Services on VI resource provider"
#$createResourceUri = "https://management.azure.com/subscriptions/${env:subscriptionId}/resourceGroups/${env:resourceGroup}/providers/Microsoft.VideoIndexer/accounts/${env:videoIndexerAccountName}/CreateExtensionDependencies?api-version=${viApiVersion}"

#$result = $(az rest --method post --uri $createResourceUri) | ConvertFrom-Json


#$getSecretsUri="https://management.azure.com/subscriptions/${env:subscriptionId}/resourceGroups/${env:resourceGroup}/providers/Microsoft.VideoIndexer/accounts/${env:videoIndexerAccountName}/ListExtensionDependenciesData?api-version=$viApiVersion"
#while ($null -eq $csResourcesData) {
#    Write-Host "Retrieving Cognitive Service Credentials..."
#    $csResourcesData=$(az rest --method post --uri $getSecretsUri) | ConvertFrom-Json
#    Start-Sleep -Seconds 10
#}
#Write-Host

Write-Host "Getting VM public IP address..."
$hostname = hostname
$ipAddresses = az vm list-ip-addresses -g $env:resourceGroup -n $hostname | ConvertFrom-Json
$ipAddress = $ipAddresses.virtualMachine.network.publicIpAddresses[0].ipAddress

Write-Host "Installing Video Indexer extension into AKS EE cluster."
az k8s-extension create --name $extensionName `
                        --extension-type Microsoft.VideoIndexer `
                        --scope cluster `
                        --release-namespace $namespace `
                        --cluster-name $clusterName `
                        --resource-group $Env:resourceGroup `
                        --cluster-type connectedClusters `
                        --version $version `
                        --release-train "preview" ` 
                        --auto-upgrade-minor-version false `
                        --config "videoIndexer.endpointUri=https://$ipAddress" `
                        --config "videoIndexer.accountId=${Env:videoIndexerAccountId}" `
                        --config "storage.storageClass=$storageClass" `
                        --config "storage.accessMode=ReadWriteMany"
                        --config AI.nodeSelector."beta\\.kubernetes\\.io/os"=linux \
                        --config "ViAi.gpu.enabled=$enable_gpu" \
                        --config "ViAi.gpu.tolerations.key=nvidia.com/gpu" \
                        --config "ViAi.gpu.nodeSelector.workload=summarization"

                        # Allow access to the frontend through the VM NIC interface
Write-Host "Adding Windows Defender firewall rule for VI frontend..."
New-NetFirewallRule -DisplayName "Allow Inbound Port 80" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow Inbound Port 443" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow

Write-Host "Adding port forward for VI frontend..."
Start-Sleep -Seconds 20
$ing = kubectl get ing video-indexer-vi-arc -n $namespace -o json | ConvertFrom-Json
$ingIp = $ing.status.loadBalancer.ingress.ip
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=80 connectaddress=$ingIp connectport=80
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=443 connectaddress=$ingIp connectport=443

# Kill the open PowerShell monitoring kubectl get pods
Stop-Process -Id $kubectlMonShell.Id

# Install Postman
choco install postman /y -Force

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "LogonScript" -Confirm:$false
Start-Sleep -Seconds 5
$ProgressPreference = "Continue"

# Changing to Client VM wallpaper
$imgPath = "C:\Temp\wallpaper.png"
$code = @' 
using System.Runtime.InteropServices; 
namespace Win32{ 
    
     public class Wallpaper{ 
        [DllImport("user32.dll", CharSet=CharSet.Auto)] 
         static extern int SystemParametersInfo (int uAction , int uParam , string lpvParam , int fuWinIni) ; 
         
         public static void SetWallpaper(string thePath){ 
            SystemParametersInfo(20,0,thePath,3); 
         }
    }
 } 
'@

add-type $code 
[Win32.Wallpaper]::SetWallpaper($imgPath)
Stop-Process -Name powershell -Force

Stop-Transcript
