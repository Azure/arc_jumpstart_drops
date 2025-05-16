# Creating Log File
Start-Transcript -Path C:\Temp\ArcInstallScript.log

# Azure Login 

az login --service-principal -u $Env:appId -p $Env:password --tenant $Env:tenantId
az account set -s $Env:SubscriptionId

# Configure hosts file for Private link endpoints resolution

$file = "C:\Windows\System32\drivers\etc\hosts"
$ArcPe = "Arc-PE"
$ArcRG = "arc-azure-rg"
$AMPLSPe = "ampls-pe"
$AMPLSRG = "arc-azure-rg"

try {
    $arcDnsData = az network private-endpoint dns-zone-group list `
        --endpoint-name $ArcPe `
        --resource-group $ArcRG `
        -o json | ConvertFrom-Json

    $gisfqdn   = $arcDnsData[0].privateDnsZoneConfigs[0].recordSets[0].fqdn.Replace('.privatelink','')
    $gisIP     = $arcDnsData[0].privateDnsZoneConfigs[0].recordSets[0].ipAddresses[0]

    $hisfqdn   = $arcDnsData[0].privateDnsZoneConfigs[0].recordSets[1].fqdn.Replace('.privatelink','')
    $hisIP     = $arcDnsData[0].privateDnsZoneConfigs[0].recordSets[1].ipAddresses[0]

    $agentfqdn = $arcDnsData[0].privateDnsZoneConfigs[1].recordSets[0].fqdn.Replace('.privatelink','')
    $agentIp   = $arcDnsData[0].privateDnsZoneConfigs[1].recordSets[0].ipAddresses[0]

    $gasfqdn   = $arcDnsData[0].privateDnsZoneConfigs[1].recordSets[1].fqdn.Replace('.privatelink','')
    $gasIp     = $arcDnsData[0].privateDnsZoneConfigs[1].recordSets[1].ipAddresses[0]

    $dpfqdn    = $arcDnsData[0].privateDnsZoneConfigs[2].recordSets[0].fqdn.Replace('.privatelink','')
    $dpIp      = $arcDnsData[0].privateDnsZoneConfigs[2].recordSets[0].ipAddresses[0]
} catch {
    Write-Host "Error during integration ARC PE"
}

try {
    $amplsDnsData = az network private-endpoint dns-zone-group list `
        --endpoint-name $AMPLSPe `
        --resource-group $AMPLSRG `
        -o json | ConvertFrom-Json

    $records = $amplsDnsData[0].privateDnsZoneConfigs[0].recordSets

    $ampls0fqdn = $records[0].fqdn.Replace('.privatelink','')
    $ampls0ip   = $records[0].ipAddresses[0]

    $ampls1fqdn = $records[1].fqdn.Replace('.privatelink','')
    $ampls1ip   = $records[1].ipAddresses[0]

    $ampls2fqdn = $records[2].fqdn.Replace('.privatelink','')
    $ampls2ip   = $records[2].ipAddresses[0]

    $ampls3fqdn = $records[3].fqdn.Replace('.privatelink','')
    $ampls3ip   = $records[3].ipAddresses[0]

    $ampls4fqdn = $records[4].fqdn.Replace('.privatelink','')
    $ampls4ip   = $records[4].ipAddresses[0]

    $ampls5fqdn = $records[5].fqdn.Replace('.privatelink','')
    $ampls5ip   = $records[5].ipAddresses[0]

    $ampls6fqdn = $records[6].fqdn.Replace('.privatelink','')
    $ampls6ip   = $records[6].ipAddresses[0]

    $ampls7fqdn = $records[7].fqdn.Replace('.privatelink','')
    $ampls7ip   = $records[7].ipAddresses[0]

    $ampls8fqdn = $records[8].fqdn.Replace('.privatelink','')
    $ampls8ip   = $records[8].ipAddresses[0]

    $ampls9fqdn = $records[9].fqdn.Replace('.privatelink','')
    $ampls9ip   = $records[9].ipAddresses[0]

} catch {
    Write-Host "Error during integration AMPLS PE"
}
try {
    $hostfile = Get-Content $file

    # Arc PE
    $hostfile += "$gisIP $gisfqdn"
    $hostfile += "$hisIP $hisfqdn"
    $hostfile += "$agentIp $agentfqdn"
    $hostfile += "$gasIp $gasfqdn"
    $hostfile += "$dpIp $dpfqdn"

    # AMPLS PE
$hostfile += "$ampls0ip $ampls0fqdn"
$hostfile += "$ampls1ip $ampls1fqdn"
$hostfile += "$ampls2ip $ampls2fqdn"
$hostfile += "$ampls3ip $ampls3fqdn"
$hostfile += "$ampls4ip $ampls4fqdn"
$hostfile += "$ampls5ip $ampls5fqdn"
$hostfile += "$ampls6ip $ampls6fqdn"
$hostfile += "$ampls7ip $ampls7fqdn"
$hostfile += "$ampls8ip $ampls8fqdn"
$hostfile += "$ampls9ip $ampls9fqdn"

    Set-Content -Path $file -Value $hostfile -Force
    Write-Host "File host update"
} catch {
    Write-Host "Error During integration Host"
}


## Configure the OS to allow Azure Arc Agent to be deploy on an Azure VM

Write-Host "Configure the OS to allow Azure Arc connected machine agent to be deploy on an Azure VM"
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
& "$Env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" connect `
--resource-group $Env:resourceGroup `
--tenant-id $Env:tenantId `
--location $Env:Location `
--subscription-id $Env:SubscriptionId `
--cloud "AzureCloud" `
--private-link-scope $Env:PLscope `
--service-principal-id $Env:appId `
--service-principal-secret $Env:password `
--correlation-id "e5089a61-0238-48fd-91ef-f67846168001" `
--tags "Project=jumpstart_azure_arc_servers" 

# Remove schedule task
Unregister-ScheduledTask -TaskName "LogonScript" -Confirm:$False
Stop-Process -Name powershell -Force
