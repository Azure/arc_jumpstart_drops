<#
Prerequisites:
- PowerShell 7.2+ (Runbook)
- Azure CLI must be available in the environment
- Modules Az.Accounts >= 2.7.5 and Az.ResourceGraph must be installed in the Automation Account
- Managed Identity must be enabled for the Automation Account
- The Managed Identity must have permissions to modify Azure Arc machines
#>

# --- Structured logging function ---
function Write-Log {
    param (
        [string] $Level,
        [string] $Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$timestamp][$Level] $Message"
}

# --- Environment validation ---
function Validate-Environment {
    if ($PSVersionTable.PSVersion -lt [Version]"7.2") {
        Write-Log -Level "ERROR" -Message "PowerShell 7.2 or higher is required."
        throw
    }

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Log -Level "ERROR" -Message "Azure CLI is not available in the environment."
        throw
    }

    $requiredModules = @("Az.Accounts", "Az.ResourceGraph")
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Log -Level "ERROR" -Message "Required module '$module' is not installed."
            throw
        }
    }

    Write-Log -Level "INFO" -Message "Environment successfully validated."
}

# --- Authentication ---
function Authenticate-Azure {
    try {
        Write-Log -Level "INFO" -Message "Authenticating to Azure using managed identity (PowerShell)..."
        Connect-AzAccount -Identity | Out-Null

        Write-Log -Level "INFO" -Message "Authenticating to Azure CLI using managed identity..."
        az login --identity --allow-no-subscriptions | Out-Null

        Write-Log -Level "INFO" -Message "Authentication completed successfully."
    }
    catch {
        Write-Log -Level "ERROR" -Message "Authentication error: $($_.Exception.Message)"
        throw
    }
}

# --- Ensure arcdata extension is installed ---
function Ensure-ArcDataExtension {
    try {
        $extensions = az extension list --output json | ConvertFrom-Json
        if (-not ($extensions | Where-Object { $_.name -eq "arcdata" })) {
            Write-Log -Level "INFO" -Message "Installing 'arcdata' extension..."
            az extension add --name arcdata --yes --allow-preview true | Out-Null
            Write-Log -Level "INFO" -Message "'arcdata' extension installed successfully."
        }
        else {
            Write-Log -Level "INFO" -Message "'arcdata' extension is already installed."
        }
    }
    catch {
        Write-Log -Level "ERROR" -Message "Error checking/installing arcdata extension: $($_.Exception.Message)"
        throw
    }
}

# --- Enable LeastPrivilege FeatureFlag ---
function Enable-FeatureFlag {
    param (
        [string] $ResourceGroup,
        [string] $MachineName
    )

    try {
        az sql server-arc extension feature-flag set `
            --name LeastPrivilege `
            --enable true `
            --resource-group $ResourceGroup `
            --machine-name $MachineName `
            --verbose | Out-Null

        return "Success"
    }
    catch {
        return "Failure: $($_.Exception.Message)"
    }
}

# --- Query Resource Graph ---
function Query-Machines {
    param (
        [string] $SubscriptionId
    )

    $query = @"
resources
| where type == "microsoft.hybridcompute/machines/extensions"
| where name == "WindowsAgent.SqlServer"
| extend props = parse_json(properties)
| extend settings = props.settings
| extend sqlDiscovered = tostring(settings.SqlManagement.IsEnabled)
| where sqlDiscovered == "true"
| extend machineName = tolower(extract(@"machines/([^/]+)/extensions", 1, id))
| join kind=inner (
    resources
    | where type == "microsoft.hybridcompute/machines"
    | extend machineId = id,
             machineName = tolower(name),
             machineStatus = tolower(tostring(properties.status)),
             lastStatusChange = properties.lastStatusChange
    | where machineStatus == "connected"
    | project machineId, machineName, machineStatus, lastStatusChange
) on machineName
| extend featureFlagsArray = iif(isnull(settings.FeatureFlags) or array_length(settings.FeatureFlags) == 0, dynamic([{"Name":null,"Enable":null}]), settings.FeatureFlags)
| mv-expand featureFlags = featureFlagsArray to typeof(dynamic)
| extend featureName = tostring(featureFlags.Name), featureEnabled = tostring(featureFlags.Enable)
| where isempty(featureEnabled) or featureEnabled == "false"
| project machineName, resourceGroup, subscriptionId, featureName, featureEnabled, sqlDiscovered, machineStatus, lastStatusChange, id, machineId
"@

    return Search-AzGraph -Query $query -Subscription $SubscriptionId
}

# --- Process machines in a subscription ---
function Process-MachinesInSubscription {
    param (
        [string] $SubscriptionId
    )

    Write-Log -Level "INFO" -Message "Querying machines in subscription ${SubscriptionId}..."
    $machines = Query-Machines -SubscriptionId $SubscriptionId

    if (-not $machines -or $machines.Count -eq 0) {
        Write-Log -Level "INFO" -Message "No machines with disabled/missing FeatureFlags and 'connected' status found in subscription ${SubscriptionId}."
        return
    }

    foreach ($item in $machines) {
        Write-Log -Level "INFO" -Message "Processing machine: $($item.machineName) in resource group $($item.resourceGroup)..."

        $updateStatus = Enable-FeatureFlag -ResourceGroup $item.resourceGroup -MachineName $item.machineName

        $output = [PSCustomObject]@{
            Name           = $item.machineName
            ResourceGroup  = $item.resourceGroup
            SubscriptionId = $item.subscriptionId
            FeatureName    = $item.featureName
            FeatureEnabled = $item.featureEnabled
            SqlDiscovered  = $item.sqlDiscovered
            Status         = $item.machineStatus
            LastChange     = $item.lastStatusChange
            UpdateStatus   = $updateStatus
        }

        # Single-line CSV-style output
        $csvLine = ($output | ConvertTo-Csv -NoTypeInformation)[1]
        Write-Log -Level "RESULT" -Message $csvLine
    }
}

# --- Main execution ---
try {
    Validate-Environment
    Authenticate-Azure
    Ensure-ArcDataExtension

    $subscriptions = Get-AzSubscription

    foreach ($sub in $subscriptions) {
        Write-Log -Level "INFO" -Message "Setting context for subscription: $($sub.Name) ($($sub.Id))"
        Set-AzContext -SubscriptionId $sub.Id | Out-Null

        Process-MachinesInSubscription -SubscriptionId $sub.Id
    }

    Write-Log -Level "INFO" -Message "Execution completed successfully."
}
catch {
    Write-Log -Level "FATAL" -Message "Execution failed: $($_.Exception.Message)"
    throw
}
