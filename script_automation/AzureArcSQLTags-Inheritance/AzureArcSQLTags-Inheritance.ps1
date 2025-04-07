```powershell
<#
.SYNOPSIS
This script checks and updates tags for Azure Arc SQL Server instances based on the tags of associated hybrid machines.

.DESCRIPTION
The script connects to Azure using a user-assigned managed identity and retrieves Azure Arc SQL Server instances and their associated hybrid machines. It compares the tags of the hybrid machines with the tags of the SQL Server instances and determines the compliance status. If any non-compliant instances are found, it updates the tags of the SQL Server instances to match the tags of the hybrid machines.

.PARAMETER ResourceGroupName
The name of the resource group containing the Azure Arc SQL Server instances.

.PARAMETER SubscriptionID
The ID of the subscription containing the Azure Arc SQL Server instances.

.PARAMETER tagName
The name of the tag to compare and update.

.EXAMPLE
.\AzureArcSQLTags-Inheritance.ps1 -ResourceGroupName "myResourceGroup" -SubscriptionID "12345678-1234-1234-1234-1234567890ab" -tagName "centro_de_custo"

.NOTES
- This script requires the Az.Accounts and Az.ResourceGraph modules to be installed.
- The script requires a user-assigned managed identity with appropriate permissions to connect to Azure and update tags.
- The script uses the Azure Resource Graph to query and retrieve the Azure Arc SQL Server instances and their associated hybrid machines.
- The script updates the tags of the SQL Server instances using the Update-AzTag cmdlet.
- The compliance status is determined based on the comparison of tags between the hybrid machines and SQL Server instances.
- Non-compliant instances are identified and their tags are updated to match the tags of the associated hybrid machines.
#>

# Define the parameters to be required at runtime
param (
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,  # Resource Group Name

    [Parameter(Mandatory=$true)]
    [string]$SubscriptionID,  # Subscription ID

    [Parameter(Mandatory=$true)]
    [string]$tagName  # Example centro_de_custo Tag Name
)

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process | Out-Null

try {
    # Connect to Azure with user-assigned managed identity
    $AzureContext = (Connect-AzAccount -Identity -AccountId REPLACE_WITH_YOUR_ID).context
    
    # Set and store context with the specified subscription
    $AzureContext = Set-AzContext -SubscriptionName $SubscriptionID -DefaultProfile $AzureContext
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Executes the query and stores the result in the variable $result
$query = @"
resources
| where type =~ 'Microsoft.AzureArcData/SqlServerInstances'
| where resourceGroup == '$ResourceGroupName' // Filter by Resource Group
| extend subscriptionId = subscriptionId, 
         arcInstanceContainerId = tostring(split(properties['containerResourceId'], '/')[8])  // Capture containerResourceId of Arc resource
| join kind=inner (
    resources
    | where type =~ 'Microsoft.HybridCompute/machines'
    | extend hybridMachineName = name,  // Capture the hybrid machine name
             hybridMachineTag = coalesce(tags['$tagName'], '') // Capture the tag of the hybrid machine, handling nulls
) on `$left.arcInstanceContainerId == `$right.hybridMachineName and `$left.subscriptionId == `$right.subscriptionId
| extend sqlInstanceTag = coalesce(tags['$tagName'], '') // Capture the tag of the SQL Instance, handling nulls
| extend tagsDiffer = sqlInstanceTag != hybridMachineTag // Add a field to indicate if the tags differ
| extend complianceStatus = case(
    isnull(sqlInstanceTag) or isnull(hybridMachineTag), 'Nao Conformidade',  // If any tag is null, it's non-compliant
    tagsDiffer, 'Nao Conformidade',  // If the tags differ, it's non-compliant
    'Em Conformidade'  // Otherwise, it's compliant
)
| project 
    ['Azure Arc VM Source Name'] = hybridMachineName,  // Hybrid machine name
    ['Azure Arc VM Source Name Tag'] = hybridMachineTag, // Azure Arc VM Source Name Tag
    ['SQL Instance ID'] = id, // SQL Instance ID
    ['SQL Instance'] = name,  // SQL Server and SQL Instance name
    ['SQL Instance Tag'] = sqlInstanceTag, // SQL Instance Tag
    ['Azure Arc VM Source Name by SQL Instance'] = arcInstanceContainerId,  // Container ID associated with the Arc resource
    ['Tags Differ'] = tagsDiffer,  // Add a field to indicate if the tags differ
    ['Compliance Status'] = complianceStatus  // Add a field to indicate the compliance status
"@

# Execute the query
$result = Search-AzGraph -Query $query
    
# Project the desired columns
$projectedResult = $result | Select-Object 'Azure Arc VM Source Name', 'Azure Arc VM Source Name Tag', 'SQL Instance ID', 'SQL Instance', 'SQL Instance Tag', 'Azure Arc VM Source Name by SQL Instance', 'Tags Differ', 'Compliance Status'

# Filter the projected result based on Compliance Status
$filteredResult = $projectedResult | Where-Object { $_.'Compliance Status' -eq 'Nao Conformidade' }

Write-Output "Recursos em Nao Conformidade"
$filteredResult

# Check if the filtered result is empty
if ($filteredResult.Count -eq 0) {
    Write-Output "No results found in the query."
}
else {
    # Loop through resources to add tags
    foreach ($resource in $filteredResult) {
        $id = $resource.'SQL Instance ID'
        $arcVMName = $resource.'Azure Arc VM Source Name'
        
        # Use the parameter $tagName to create the tag
        $tag = @{
            $tagName = $resource.'Azure Arc VM Source Name Tag' # Use the tag value from the parameter
        }
        # Apply the tag to the SQL instance
        Update-AzTag -Tag $tag -ResourceId $id -Operation Merge -Verbose
        
        # Output the modified resource information
        Write-Output "Resource modified: SQL Instance ID: $id, Tag: $tagName = $tag.$tagName"
    }
}
```
