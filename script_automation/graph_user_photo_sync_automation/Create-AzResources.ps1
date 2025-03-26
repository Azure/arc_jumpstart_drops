#create Resource Group, Automation Account, and System Managed Identity
Connect-AzAccount -Subscription 'Your Subscription Name'

#create Resource Group
$rgname = "rgAzureTesting"
$location = "westus2"
New-AzResourceGroup -Name $rgname -Location $location

#create Automation Account
$accountName = 'aaAzureTesting'
$rgName = 'rgAzureTesting'
$location = 'westus2'
New-AzAutomationAccount -Name $accountName -ResourceGroupName $rgName -Location $location

#create System Managed Identity
$accountName = 'aaAzureTesting'
$rgName = 'rgAzureTesting'
Set-AzAutomationAccount -Name $accountName -ResourceGroupName $rgName -AssignSystemIdentity

```powershell

#Connect to Graph for assigning permissions to Managed Identity
$TenantId = 'Your Tenant Id'
Connect-MgGraph -TenantId $TenantId

#Assign the Graph Permissions needed for updating user info
$GraphApp = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'"
$ManagedIdentityApp = Get-MgServicePrincipal -Filter "displayName eq 'aaAzureTesting'"
$Permissions = @(
    "Directory.Read.All",
    "User.ReadWrite.All",
    "ProfilePhoto.ReadWrite.All"
)

$AppRoles = $GraphApp.AppRoles | Where-Object `
{($_.Value -in $Permissions) -and ($_.AllowedMemberTypes -contains "Application")}

foreach ($AppRole in $AppRoles) {
    $AppRoleAssignment = @{
        "PrincipalId" = $ManagedIdentityApp.id
        "ResourceId" = $GraphApp.id
        "AppRoleId" = $AppRole.id
    }

    New-MgServicePrincipalAppRoleAssignment `
     -ServicePrincipalId $AppRoleAssignment.PrincipalId `
     -BodyParameter $AppRoleAssignment -verbose
}