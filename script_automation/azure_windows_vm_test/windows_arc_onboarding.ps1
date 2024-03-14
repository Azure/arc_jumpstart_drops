# Variables
$subscriptionId = "<Provide your subscription ID>"
$appId = "<Provide your Service Principal App ID>"
$password = "<Provide your service principal password>"
$tenantId = "<Provide your Tenant ID>"
$resourceGroup = "<Provide your resource group name>"
$location = "<Provide the Azure Region>"

New-Item -Path "C:\" -Name "tmp" -ItemType "directory" -Force

Start-Transcript -Path C:\tmp\LogonScript.log

## Configure the OS to allow Azure Arc Agent to be deploy on an Azure VM

Write-Host "Configure the OS to allow Azure Arc Agent to be deploy on an Azure VM"
Set-Service WindowsAzureGuestAgent -StartupType Disabled -Verbose
Stop-Service WindowsAzureGuestAgent -Force -Verbose
New-NetFirewallRule -Name BlockAzureIMDS -DisplayName "Block access to Azure IMDS" -Enabled True -Profile Any -Direction Outbound -Action Block -RemoteAddress 169.254.169.254 

## Azure Arc agent Installation

Write-Host "Onboarding to Azure Arc"
# Download the package
function download() {$ProgressPreference="SilentlyContinue"; Invoke-WebRequest -Uri https://aka.ms/AzureConnectedMachineAgent -OutFile AzureConnectedMachineAgent.msi}
download

# Install the package
msiexec /i AzureConnectedMachineAgent.msi /l*v installationlog.txt /qn | Out-String

# Run connect command
 & "$env:ProgramFiles\AzureConnectedMachineAgent\azcmagent.exe" connect `
 --service-principal-id $appId `
 --service-principal-secret $password `
 --resource-group $resourceGroup `
 --tenant-id $tenantId `
 --location $location `
 --subscription-id $subscriptionId `
 --tags "Project=jumpstart_azure_arc_servers" `
 --correlation-id "d009f5dd-dba8-4ac7-bac9-b54ef3a6671a"
