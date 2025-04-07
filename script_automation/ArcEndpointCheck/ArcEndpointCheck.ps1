# Purpose: This script checks the connectivity and status of Azure endpoints, including both static and dynamic endpoints, 
# and validates Azure Arc functionality. It performs DNS resolution, network connectivity, and HTTP request tests, 
# logging the results for review.

# Disclaimer: This script is intended for use in environments where connectivity to Azure endpoints and Azure Arc services 
# needs to be validated. It relies on internet access to fetch dynamic endpoints and assumes the presence of `azcmagent.exe` 
# for Azure Arc checks. Results are logged to a specified file, and proper access control on logs is advised.

# Define the region
$region = "brazilsouth"

# Define the log file path
$logFilePath = "C:\temp\Arclogfile.txt"

# Ensure log file exists before clearing
if (-Not (Test-Path $logFilePath)) {
    New-Item -ItemType File -Path $logFilePath -Force | Out-Null
} else {
    Clear-Content -Path $logFilePath -ErrorAction SilentlyContinue
}

# Write start of the log
"Script started at $(Get-Date)" | Out-File -FilePath $logFilePath -Append

# Define the list of static endpoints
$staticEndpoints = @(
    "login.windows.net", "login.microsoftonline.com", "pas.windows.net", # AAD
    "management.azure.com", # ARM
    "global.handler.control.monitor.azure.com", # AMA
    "gbl.his.arc.azure.com", "agentserviceapi.guestconfiguration.azure.com", # Arc
    "dataprocessingservice.$region.arcdataservices.com", "telemetry.$region.arcdataservices.com" # ArcData and Telemetry
)

# Fetch dynamic endpoints for the specified region
try {
    $logMessage = "Running: Invoke-WebRequest -Uri 'https://guestnotificationservice.azure.com/urls/allowlist?api-version=2020-01-01&location=$region'"
    $logMessage | Out-File -FilePath $logFilePath -Append

    $response = Invoke-WebRequest -Uri "https://guestnotificationservice.azure.com/urls/allowlist?api-version=2020-01-01&location=$region" -ErrorAction Stop
    $dynamicEndpoints = ($response.Content -replace '\[|\]|"|\\n','').Split(',')
    "Dynamic endpoints fetched: $($dynamicEndpoints -join ', ')" | Out-File -FilePath $logFilePath -Append
} catch {
    "Error fetching dynamic endpoints: $_" | Out-File -FilePath $logFilePath -Append
    $dynamicEndpoints = @()
}

# Combine static and dynamic endpoints
$allEndpoints = $staticEndpoints + $dynamicEndpoints

# List of allowed endpoints for HTTP request
$allowedEndpoints = @(
    "login.windows.net",
    "login.microsoftonline.com",
    "dataprocessingservice.$region.arcdataservices.com",
    "telemetry.$region.arcdataservices.com"
)

# Filter the dynamic endpoints to match the allowed list
$filteredDynamicEndpoints = $allowedEndpoints

# Combine static endpoints with the filtered dynamic endpoints for HTTP requests
$finalEndpointsForRequest = $filteredDynamicEndpoints

# Iterate over all endpoints to test connectivity, DNS resolution, and HTTP response for the filtered dynamic endpoints
foreach ($endpoint in $allEndpoints) {
    $trimmedEndpoint = $endpoint.Trim()

    # DNS resolution test
    $dnsLogMessage = "Testing DNS resolution for: $($trimmedEndpoint)"
    $dnsLogMessage | Out-File -FilePath $logFilePath -Append

    try {
        $logMessage = "Running: Resolve-DnsName -Name $($trimmedEndpoint)"
        $logMessage | Out-File -FilePath $logFilePath -Append
        
        $dnsResult = Resolve-DnsName -Name $trimmedEndpoint -ErrorAction Stop
        $dnsOutput = "Success: DNS resolution succeeded for $($trimmedEndpoint): $($dnsResult.Name)"
        Write-Host $dnsOutput -ForegroundColor Green
        $dnsOutput | Out-File -FilePath $logFilePath -Append
    } catch {
        $dnsError = "Error: DNS resolution failed for $($trimmedEndpoint) - $_"
        Write-Host $dnsError -ForegroundColor Red
        $dnsError | Out-File -FilePath $logFilePath -Append
    }

    # Connectivity test
    $connectivityLogMessage = "Testing connectivity for: $($trimmedEndpoint)"
    $connectivityLogMessage | Out-File -FilePath $logFilePath -Append

    try {
        $logMessage = "Running: Test-Connection -ComputerName $($trimmedEndpoint) -Count 1"
        $logMessage | Out-File -FilePath $logFilePath -Append
        
        $pingResult = Test-Connection -ComputerName $trimmedEndpoint -Count 1 -ErrorAction Stop
        $pingOutput = "Success: Connectivity succeeded for $($trimmedEndpoint): Response time: $($pingResult.ResponseTime)ms"
        Write-Host $pingOutput -ForegroundColor Green
        $pingOutput | Out-File -FilePath $logFilePath -Append
    } catch {
        $pingError = "Error: Connectivity test failed for $($trimmedEndpoint) - $_"
        Write-Host $pingError -ForegroundColor Red
        $pingError | Out-File -FilePath $logFilePath -Append
    }

    "----------------------------------------" | Out-File -FilePath $logFilePath -Append
}

# HTTP request test (only for filtered dynamic endpoints)
foreach ($endpoint in $finalEndpointsForRequest) {
    $trimmedEndpoint = $endpoint.Trim()

    # HTTP request test
    $httpLogMessage = "Testing HTTP request for: $($trimmedEndpoint)"
    $httpLogMessage | Out-File -FilePath $logFilePath -Append

    try {
        # Measure response time and check for 401
        $response_time = Measure-Command { 
            $response = Invoke-WebRequest -Uri "https://$trimmedEndpoint" -Method Get
        }

        if ($response.StatusCode -eq 401) {
            # If status code is 401, treat it as expected and log it as such
            $httpResult = "Expected (401)"
            $httpOutput = "Success: HTTP request succeeded for $($trimmedEndpoint): $($httpResult) - Response time: $($response_time.TotalSeconds) seconds"
            Write-Host $httpOutput -ForegroundColor Green
            $httpOutput | Out-File -FilePath $logFilePath -Append
        } else {
            # For other status codes, log the actual status code
            $httpResult = "Unexpected Status: $($response.StatusCode)"
            $httpOutput = "Success: HTTP request succeeded for $($trimmedEndpoint): $($httpResult) - Response time: $($response_time.TotalSeconds) seconds"
            Write-Host $httpOutput -ForegroundColor Green
            $httpOutput | Out-File -FilePath $logFilePath -Append
        }
    } catch {
        # Handle exceptions and log them
        if ($_.Exception.Message -like "*401*") {
            # If 401 is encountered in the exception message, treat it as expected
            $httpResult = "Expected (401)"
            $httpError = "Success: HTTP request succeeded for $($trimmedEndpoint) - $httpResult"
            Write-Host $httpError -ForegroundColor Green
            $httpError | Out-File -FilePath $logFilePath -Append
        } else {
            # For other exceptions, log the error message
            $httpResult = "Error: $_"
            $httpError = "Error: HTTP request failed for $($trimmedEndpoint) - $httpResult"
            Write-Host $httpError -ForegroundColor Red
            $httpError | Out-File -FilePath $logFilePath -Append
        }
    }

    "----------------------------------------" | Out-File -FilePath $logFilePath -Append
}

# Public and Private Azure Arc check
$publicAzureArcMessage = "Running public Azure Arc check..."
$publicAzureArcMessage | Out-File -FilePath $logFilePath -Append

# Check if azcmagent.exe exists in the default path
$azcmagentPath = Join-Path $env:PROGRAMFILES "AzureConnectedMachineAgent\azcmagent.exe"
if (Test-Path $azcmagentPath) {
    $logMessage = "Running: & $azcmagentPath check --location $($region) --cloud AzureCloud --extensions sql --enable-pls-check"
    $logMessage | Out-File -FilePath $logFilePath -Append
    
    # Execute azcmagent from the correct path
    $azcmAgentResult = & $azcmagentPath check --location $($region) --cloud AzureCloud --extensions sql --enable-pls-check
    $azcmAgentResult | Out-File -FilePath $logFilePath -Append
} else {
    $errorMessage = "Error: azcmagent.exe not found in $azcmagentPath"
    $errorMessage | Out-File -FilePath $logFilePath -Append
}

# Write end of the log
"Script finished at $(Get-Date)" | Out-File -FilePath $logFilePath -Append
