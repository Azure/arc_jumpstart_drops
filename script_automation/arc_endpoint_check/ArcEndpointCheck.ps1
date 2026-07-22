<#
.SYNOPSIS
    Validates Azure Arc connectivity, proxy behavior, agent local health, DNS, TCP, HTTP,
    TLS, PKI bypass, and optional platform-specific metadata endpoints.

.DESCRIPTION
    Refactored version of Arc endpoint validation with safer semantics for explicit proxy
    environments and clearer platform separation.

    In Private mode, this script distinguishes the Azure Arc private connectivity path from
    Microsoft Entra ID and Azure Resource Manager control-plane traffic. Azure Arc Private
    Link Scope does not carry ARM traffic by default, so a failed path to
    management.azure.com can be reported as a non-blocking WARN when azcmagent shows no
    critical Arc connectivity failures and Arc private-capable endpoints remain healthy.

    Key improvements:
      - Proxy-aware TCP result classification (avoids false FAIL for direct TCP in proxy mode)
      - Agent local health section (services, version, config, last himds log lines)
      - Optional platform checks for AzureLocal / AzureStackHub / AzureVM
      - Reduced reliance on static endpoint assumptions when azcmagent is available
      - More conservative TLS/cipher reporting
      - Private-mode handling that separates Arc private-link health from ARM control-plane health

.PARAMETER Region
    Azure region. Auto-detected from azcmagent when possible.

.PARAMETER Mode
    Auto | Public | Private | Gateway. Default: Auto.

.PARAMETER Platform
    Auto | Arc | AzureLocal | AzureStackHub | AzureVM. Default: Auto.

.PARAMETER ProxyUrl
    Override proxy URL. Auto-detected if omitted.

.PARAMETER LogFilePath
    Log file path. Default: C:\temp\ArcEndpointCheck_<computer>.txt.

.PARAMETER SkipPKI
    Skips PKI/OCSP/CRL testing.

.PARAMETER SkipExtensions
    Skips extension endpoint testing.

.PARAMETER CheckIncludeAll
    Makes azcmagent check use '--extensions all --include-all'.

.PARAMETER SkipAgentHealth
    Skips local agent health inspection.

.EXAMPLE
    .\arc-endpoint-check-revised.ps1

.EXAMPLE
    .\arc-endpoint-check-revised.ps1 -Region brazilsouth -Mode Private

.EXAMPLE
    .\arc-endpoint-check-revised.ps1 -Platform AzureLocal -Mode Gateway -ProxyUrl http://10.0.1.4:8443
#>

[CmdletBinding()]
param(
    [string]$Region = '',

    [ValidateSet('Auto', 'Public', 'Private', 'Gateway')]
    [string]$Mode = 'Auto',

    [ValidateSet('Auto', 'Arc', 'AzureLocal', 'AzureStackHub', 'AzureVM')]
    [string]$Platform = 'Auto',

    [string]$ProxyUrl,

    [string]$LogFilePath = "C:\temp\ArcEndpointCheck_$($env:COMPUTERNAME).txt",

    [switch]$SkipPKI,
    [switch]$SkipExtensions,
    [switch]$CheckIncludeAll,
    [switch]$SkipAgentHealth
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$logDir = Split-Path -Path $LogFilePath -Parent
if ($logDir -and -not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
Set-Content -Path $LogFilePath -Value "ArcEndpointCheck started at $(Get-Date -Format o)" -Force

$script:Stats = [ordered]@{
    DNSOK = 0; DNSWarn = 0; DNSFail = 0
    TCPOK = 0; TCPWarn = 0; TCPFail = 0
    HTTPOK = 0; HTTPWarn = 0; HTTPFail = 0
}
$script:Log = New-Object System.Collections.ArrayList
$script:Results = New-Object System.Collections.ArrayList
$script:Issues = New-Object System.Collections.ArrayList
$script:InstalledExts = @()
$script:AgentJson = $null
$script:EffectiveProxy = $null
$script:WinHttpProxy = $null
$script:WinHttpBypass = $null
$script:GatewayUrl = $null
$script:AgentConfigDump = $null
$script:ProxyMode = 'Direct'
$script:EffectiveProxyReachable = $null
$script:EffectiveProxyParseError = $null
$script:AzcmagentCheckExit = $null
$script:AzcmagentEndpointMeta = @{}
$script:AzcmagentFailedEndpoints = New-Object System.Collections.ArrayList
$script:AzcmagentChecksFailed = $null
$script:AzcmagentCriticalFailures = $null
$script:AzcmagentCoreHealthy = $null
$script:AzcmagentPrivatePathHealthy = $false
$script:PreOnboarding = $false
$script:DeferredTlsIssue = $null
$script:ScenarioSummary = @()
$script:DisclaimerLines = @(
    'Disclaimer: This script was updated with support from Azure SRE Agent.',
    'Responsible AI documentation: Microsoft Responsible AI principles and approach: https://www.microsoft.com/en-us/ai/principles-and-approach',
    'Responsible AI governance overview: Microsoft Artificial Intelligence overview / Responsible AI Standard: https://learn.microsoft.com/en-us/compliance/assurance/assurance-artificial-intelligence',
    'Validation note: Results were tested and validated in 3 scenarios with direct user oversight, follow-up, and user-made changes during execution review.'
)
Add-Content -Path $LogFilePath -Value ''
Add-Content -Path $LogFilePath -Value '=================== DISCLAIMER ==================='
Add-Content -Path $LogFilePath -Value $script:DisclaimerLines

function Write-Banner {
    param([string]$Text)
    $w = 82
    Write-Host ''
    Write-Host ('=' * $w) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * $w) -ForegroundColor DarkCyan
}

function Write-Section {
    param([string]$Text)
    Write-Host ''
    Write-Host "  --- $Text ---" -ForegroundColor DarkGray
}

function Write-Status {
    param([string]$Label, [string]$Value, [string]$Color = 'White')
    Write-Host ("  {0,-24} {1}" -f ("${Label}:"), $Value) -ForegroundColor $Color
}

function Log {
    param(
        [string]$Msg,
        [ValidateSet('INFO', 'OK', 'WARN', 'FAIL')][string]$Level = 'INFO'
    )
    $line = "[$(Get-Date -Format HH:mm:ss)] [$Level] $Msg"
    [void]$script:Log.Add($line)
}

function Save-Log {
    if ($script:Log.Count -gt 0) {
        Add-Content -Path $LogFilePath -Value $script:Log
        $script:Log.Clear()
    }
}

function Add-Issue {
    param(
        [ValidateSet('CRITICAL', 'HIGH', 'MEDIUM', 'WARN', 'INFO')][string]$Severity,
        [string]$Category,
        [string]$Message,
        [string]$Fix = ''
    )
    [void]$script:Issues.Add([pscustomobject]@{
        Severity = $Severity
        Category = $Category
        Message = $Message
        Fix = $Fix
    })
}

function Convert-IssuesToNonBlockingWarnings {
    foreach ($issue in $script:Issues) {
        switch ($issue.Category) {
            'Proxy' {
                $issue.Severity = 'WARN'
                if ($issue.Message -notmatch 'non-blocking' -and $issue.Message -notmatch 'Private/split-network mode') {
                    $issue.Message = ($issue.Message.TrimEnd('.') + '. Treat this as a non-blocking proxy-path warning because azcmagent reported no critical Arc connectivity failures.')
                }
                if ($issue.Fix -and $issue.Fix -notmatch 'critical_failures=0' -and $issue.Fix -notmatch 'no critical Arc connectivity failures') {
                    $issue.Fix = ($issue.Fix.TrimEnd('.') + '. Do not treat this alone as Arc core outage when azcmagent reports critical_failures=0.')
                }
            }
        }
    }
}

function Add-Result {
    param(
        [string]$Endpoint,
        [string]$Group = '',
        [string]$IP = '-',
        [string]$Type = '-',
        [string]$DNS = '-',
        [string]$TCP = '-',
        [string]$HTTP = '-',
        [string]$Latency = '-',
        [string]$Notes = ''
    )
    $existing = $script:Results | Where-Object { $_.Endpoint -eq $Endpoint } | Select-Object -First 1
    if ($existing) {
        foreach ($k in 'Group','IP','Type','DNS','TCP','HTTP','Latency','Notes') {
            $v = Get-Variable -Name $k -ValueOnly
            if ($k -eq 'Group' -and [string]::IsNullOrWhiteSpace($v)) {
                continue
            }
            if ($null -ne $v -and $v -ne '-' -and $v -ne '') {
                $existing.$k = $v
            }
        }
    }
    else {
        [void]$script:Results.Add([pscustomobject]@{
            Endpoint = $Endpoint
            Group = $(if ([string]::IsNullOrWhiteSpace($Group)) { 'Core' } else { $Group })
            IP = $IP
            Type = $Type
            DNS = $DNS
            TCP = $TCP
            HTTP = $HTTP
            Latency = $Latency
            Notes = $Notes
        })
    }
}

function Test-IsValidProxyUri {
    param([string]$Candidate)
    if (-not $Candidate) { return $false }
    $uri = $null
    return [System.Uri]::TryCreate($Candidate, [System.UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @('http', 'https')
}

function Get-AzcmagentPath {
    $candidate = Join-Path $env:ProgramFiles 'AzureConnectedMachineAgent\azcmagent.exe'
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Test-IsPrivateIp {
    param([string]$Ip)
    if (-not $Ip) { return $false }
    try {
        $b = ([System.Net.IPAddress]::Parse($Ip)).GetAddressBytes()
    }
    catch {
        return $false
    }
    return ($b[0] -eq 10) -or
           ($b[0] -eq 192 -and $b[1] -eq 168) -or
           ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
           ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127)
}

function Get-OperatingSystemInfo {
    try {
        if (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue) {
            return Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        }
    }
    catch { }

    try {
        return Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Invoke-HttpSafe {
    param(
        [string]$Uri,
        [int]$TimeoutSec = 10,
        [string]$UseProxy = '',
        [switch]$NoProxy
    )

    $params = @{
        Uri = $Uri
        Method = 'Get'
        UseBasicParsing = $true
        TimeoutSec = $TimeoutSec
        ErrorAction = 'Stop'
    }

    if ($NoProxy) {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $params['NoProxy'] = $true
        }
        else {
            $saved = [System.Net.WebRequest]::DefaultWebProxy
            try {
                [System.Net.WebRequest]::DefaultWebProxy = $null
                return Invoke-WebRequest @params
            }
            finally {
                [System.Net.WebRequest]::DefaultWebProxy = $saved
            }
        }
    }
    else {
        $proxyToUse = if ($UseProxy) { $UseProxy } else { $script:EffectiveProxy }
        if ($proxyToUse) {
            $params['Proxy'] = $proxyToUse
            $params['ProxyUseDefaultCredentials'] = $true
        }
        elseif ($PSVersionTable.PSVersion.Major -ge 6) {
            $params['NoProxy'] = $true
        }
    }

    return Invoke-WebRequest @params
}

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$Port = 443,
        [int]$TimeoutMs = 5000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect($HostName, $Port, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
            $client.EndConnect($ar) | Out-Null
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Resolve-Endpoint {
    param([string]$Endpoint)
    $resolved = $null
    $err = $null
    foreach ($attempt in 1..2) {
        try {
            if (Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue) {
                $resolved = Resolve-DnsName -Name $Endpoint -ErrorAction Stop
            }
            else {
                $addresses = [System.Net.Dns]::GetHostAddresses($Endpoint) | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork }
                $resolved = @($addresses | ForEach-Object {
                    [pscustomobject]@{
                        Name = $Endpoint
                        Type = 'A'
                        IPAddress = $_.IPAddressToString
                    }
                })
            }
            $err = $null
            break
        }
        catch {
            $err = $_
            Start-Sleep -Milliseconds 250
        }
    }
    return [pscustomobject]@{
        Result = $resolved
        Error = $err
    }
}

function Get-TlsCipherInventory {
    $result = [pscustomobject]@{
        Supported = $false
        Names = @()
        Error = $null
    }

    try {
        if (-not (Get-Command -Name Get-TlsCipherSuite -ErrorAction SilentlyContinue)) {
            $result.Error = 'Get-TlsCipherSuite is not available on this PowerShell/OS version.'
            return $result
        }

        $cipherNames = @(Get-TlsCipherSuite -ErrorAction Stop | ForEach-Object { $_.Name } | Where-Object { $_ })
        $result.Supported = $true
        $result.Names = $cipherNames
        return $result
    }
    catch {
        $result.Error = $_.Exception.Message
        return $result
    }
}

function Test-AcceptableHttpCode {
    param(
        [string]$Endpoint,
        [int]$Code
    )

    $patterns = @(
        @{ Match = '^management\.azure\.com$'; Codes = @(200, 301, 302, 400, 401, 403) },
        @{ Match = '^login\.windows\.net$'; Codes = @(200, 301, 302, 400, 401, 403, 404) },
        @{ Match = '^login\.microsoftonline\.com$'; Codes = @(200, 301, 302, 400, 401, 403, 404) },
        @{ Match = '^.+\.login\.microsoft\.com$'; Codes = @(200, 301, 302, 400, 401, 403, 404) },
        @{ Match = '^dataprocessingservice\..+\.arcdataservices\.com$'; Codes = @(200, 301, 302, 400, 401, 403, 404) },
        @{ Match = '^telemetry\..+\.arcdataservices\.com$'; Codes = @(200, 301, 302, 400, 401, 403, 404) },
        @{ Match = '^oneocsp\.microsoft\.com$'; Codes = @(200, 301, 302, 400, 401, 403, 404, 405) }
    )

    foreach ($p in $patterns) {
        if ($Endpoint -match $p.Match) {
            return ($p.Codes -contains $Code)
        }
    }

    return ($Code -ge 200 -and $Code -lt 500)
}

function Convert-AzcmagentUseCaseToGroup {
    param([string]$UseCase)

    $normalizedUseCase = if ([string]::IsNullOrEmpty($UseCase)) { '' } else { $UseCase.ToLowerInvariant() }
    switch ($normalizedUseCase) {
        'core' { return 'Core' }
        'sql' { return 'SQL' }
        'paygo' { return 'PAYGO' }
        default {
            if ($UseCase) { return $UseCase.ToUpperInvariant() }
            return 'Core'
        }
    }
}

function Test-IsArcDataEndpoint {
    param([string]$Endpoint)

    if (-not $Endpoint) { return $false }
    return $Endpoint -match '^(dataprocessingservice|telemetry|defender-for-databases)\..+\.arcdataservices\.com$'
}

function Test-IsOptionalDynamicEndpoint {
    param(
        [string]$Endpoint,
        [string]$Group
    )

    if ($Group -eq 'GNS') {
        return $true
    }

    return $false
}

function Test-IsOptionalEndpoint {
    param(
        [string]$Endpoint,
        [string]$Group
    )

    if ($Endpoint -eq 'dc.services.visualstudio.com') {
        return $true
    }

    if (Test-IsArcDataEndpoint -Endpoint $Endpoint) {
        return $true
    }

    if (Test-IsOptionalDynamicEndpoint -Endpoint $Endpoint -Group $Group) {
        return $true
    }

    if ($Group -eq 'Lifecycle') {
        return (-not $script:PreOnboarding)
    }

    if ($Group -eq 'ControlPlane') {
        if ($Mode -eq 'Private') {
            return $false
        }
        return (-not $script:PreOnboarding)
    }

    return $Group -in @('SQL', 'AMA', 'MDE', 'WAC', 'KV', 'HRW', 'UM', 'GA', 'PAYGO', 'GNS')
}

function Test-IsLegacyTls12OnlyOs {
    param($OsInfo)

    if ($null -eq $OsInfo) { return $false }

    $versionText = ''
    if ($OsInfo.PSObject.Properties['Version']) {
        $versionText = [string]$OsInfo.Version
    }

    if ($versionText -match '^6\.(2|3)') {
        return $true
    }

    $caption = ''
    if ($OsInfo.PSObject.Properties['Caption']) {
        $caption = [string]$OsInfo.Caption
    }

    return ($caption -match 'Windows Server 2012')
}

function Test-IsArcDataTlsPathError {
    param(
        [string]$Endpoint,
        [string]$ErrorText
    )

    if (-not (Test-IsArcDataEndpoint -Endpoint $Endpoint)) { return $false }
    if (-not $ErrorText) { return $false }

    return ($ErrorText -match 'SEC_E_ILLEGAL_MESSAGE|unexpected or badly formatted|0x80090326')
}

function Get-AgentBypassedEndpoints {
    param(
        [string]$AgentBypass,
        [string]$Region
    )

    $bypassedEndpoints = New-Object System.Collections.ArrayList
    if (-not $AgentBypass) { return $bypassedEndpoints }

    $normalizedBypass = $AgentBypass.Trim()
    $bypassTokens = @()
    if ($normalizedBypass -match '^\s*\[') {
        try {
            $parsedBypass = $normalizedBypass | ConvertFrom-Json -ErrorAction Stop
            $bypassTokens = @($parsedBypass | ForEach-Object { [string]$_ })
        }
        catch {
            $bypassTokens = @($normalizedBypass -split ',')
        }
    }
    else {
        $bypassTokens = @($normalizedBypass -split ',')
    }

    $bypassTokens = @(
        $bypassTokens |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_.Trim().Trim('"').Trim("'").Trim('[', ']') } |
            Where-Object { $_ }
    )

    $bypassMap = @{
        'AAD' = @('login.windows.net', 'login.microsoftonline.com', 'pas.windows.net')
        'ARM' = @('management.azure.com')
        'Arc' = @('*.his.arc.azure.com', '*.guestconfiguration.azure.com')
        'ArcData' = @("dataprocessingservice.$Region.arcdataservices.com", "telemetry.$Region.arcdataservices.com")
        'AMA' = @('global.handler.control.monitor.azure.com', "$Region.handler.control.monitor.azure.com")
    }

    foreach ($token in $bypassTokens) {
        if ($bypassMap.ContainsKey($token)) {
            foreach ($ep in $bypassMap[$token]) {
                if ($bypassedEndpoints -notcontains $ep) { [void]$bypassedEndpoints.Add($ep) }
            }
        }
    }

    return $bypassedEndpoints
}

function Get-HttpStatus {
    param(
        [string]$Endpoint,
        [switch]$ForceDirect,
        [string]$ProxyOverride = ''
    )

    try {
        $response = Invoke-HttpSafe -Uri "https://$Endpoint" -TimeoutSec 10 -UseProxy $ProxyOverride -NoProxy:$ForceDirect
        return [pscustomobject]@{ Success = $true; StatusCode = [int]$response.StatusCode; Error = $null }
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
        }
        if ($statusCode -and (Test-AcceptableHttpCode -Endpoint $Endpoint -Code $statusCode)) {
            return [pscustomobject]@{ Success = $true; StatusCode = $statusCode; Error = $_.Exception.Message }
        }
        return [pscustomobject]@{ Success = $false; StatusCode = $statusCode; Error = $_.Exception.Message }
    }
}

function Get-HttpFailureDiagnosis {
    param(
        [string]$Endpoint,
        [string]$Group,
        [string]$ErrorText,
        [Nullable[int]]$StatusCode,
        [bool]$UsingExplicitProxy,
        [bool]$ForceDirect,
        [bool]$CoreHealthyNoCritical
    )

    $messageText = if ($ErrorText) { $ErrorText } else { '' }
    $proxyConfiguredButDown = $false
    if ($UsingExplicitProxy -and $script:EffectiveProxy) {
        try {
            $proxyUri = [System.Uri]$script:EffectiveProxy
            $proxyConfiguredButDown = -not (Test-TcpPort -HostName $proxyUri.Host -Port $proxyUri.Port -TimeoutMs 2500)
        }
        catch { }
    }

    $cause = 'insufficient evidence'
    $notes = 'HTTP probe failed; evidence is insufficient to attribute the failure to a specific network control.'
    $fix = 'Capture proxy/firewall logs for the failing timestamp and compare with a direct test from the same host if allowed.'
    $category = if ($UsingExplicitProxy -and -not $ForceDirect) { 'ProxyPath' } else { 'HTTP' }

    if ($proxyConfiguredButDown) {
        $cause = 'proxy endpoint unreachable'
        $notes = 'Configured proxy endpoint itself is not reachable from this host; do not attribute this probe failure to the destination endpoint yet.'
        $fix = 'Validate routing, firewall, listener state, and service health for the configured proxy endpoint before reviewing destination-specific rules.'
        $category = 'Proxy'
    }
    elseif ($StatusCode -eq 407 -or $messageText -match '407') {
        $cause = 'proxy authentication required'
        $notes = 'Proxy requested authentication for the HTTP probe.'
        $fix = 'Validate proxy authentication policy and whether machine/default credentials are accepted for this traffic.'
    }
    elseif ($StatusCode -in @(502, 503, 504)) {
        $cause = 'proxy upstream or app rule issue'
        $notes = "Proxy returned HTTP $StatusCode while attempting to reach the destination; this usually points to upstream denial, app rule mismatch, or upstream unavailability."
        $fix = 'Review proxy app rules, upstream connectivity, and destination allow policy for this endpoint.'
    }
    elseif ($messageText -match 'actively refused|refused it|connection refused|No connection could be made because the target machine actively refused it') {
        if ($UsingExplicitProxy -and -not $ForceDirect) {
            $cause = 'proxy refused connection'
            $notes = 'The proxy path refused the TCP/CONNECT attempt before the destination flow completed.'
            $fix = 'Validate the proxy listener, proxy service health, and any local firewall or route to the configured proxy.'
            $category = 'Proxy'
        }
        else {
            $cause = 'destination refused connection'
            $notes = 'The remote side actively refused the connection.'
            $fix = 'Validate destination listener expectations, intermediate filtering, and whether direct access is actually supported.'
        }
    }
    elseif ($messageText -match 'timed out|operation has timed out|The operation timed out|A task was canceled|The request was aborted') {
        $cause = 'timeout or routing issue'
        $notes = 'The probe timed out before a valid HTTP response was returned; this commonly indicates routing blackhole, silent filtering, or overloaded middlebox behavior.'
        $fix = 'Validate routing, NSG/firewall state, and whether a proxy or middlebox is silently dropping the flow.'
    }
    elseif ($messageText -match 'name could not be resolved|remote name could not be resolved|No such host is known') {
        $cause = 'dns resolution issue'
        $notes = 'The HTTP client could not resolve the target host name for this probe.'
        $fix = 'Review local DNS resolution and any proxy DNS dependency for this endpoint.'
    }
    elseif ((Test-IsArcDataTlsPathError -Endpoint $Endpoint -ErrorText $messageText) -or $messageText -match 'SEC_E_ILLEGAL_MESSAGE|0x80090326|unexpected or badly formatted|The SSL connection could not be established|authentication or decryption has failed|Could not create SSL/TLS secure channel') {
        $cause = 'tls inspection or handshake interference'
        $notes = 'The probe failed during TLS negotiation; this often points to TLS inspection, protocol handling mismatch, or middlebox interference on the path.'
        $fix = 'Review TLS inspection, certificate substitution, outbound SSL policy, and any middlebox handling on this path.'
    }
    elseif ($StatusCode -eq 403) {
        $cause = 'application layer deny'
        $notes = 'The path returned HTTP 403, which suggests the request reached an enforcing layer but was denied by policy.'
        $fix = 'Review proxy app rules, destination ACLs, and any path-based or host-based access policy for this endpoint.'
    }

    return [pscustomobject]@{
        Cause = $cause
        Notes = $notes
        Fix = $fix
        Category = $category
        ProxyConfiguredButDown = $proxyConfiguredButDown
    }
}

function Get-AgentHealth {
    param([string]$AzcmPath)

    Write-Section 'Agent Local Health'

    if (-not $AzcmPath) {
        Write-Status 'Agent health' 'Skipped - azcmagent not installed' Yellow
        return
    }

    try {
        $version = (& $AzcmPath version 2>$null | Out-String).Trim()
        if ($version) {
            Write-Status 'azcmagent version' $version Green
            Log "Agent version: $version" 'OK'
        }
    }
    catch {
        Write-Status 'azcmagent version' "Failed: $($_.Exception.Message)" Yellow
        Log "Agent version read failed: $($_.Exception.Message)" 'WARN'
    }

    try {
        $cfg = (& $AzcmPath config list 2>$null | Out-String).Trim()
        if ($cfg) {
            $script:AgentConfigDump = $cfg
            Write-Status 'Config list' 'Captured to log file' DarkGray
            Add-Content -Path $LogFilePath -Value ''
            Add-Content -Path $LogFilePath -Value '=================== AGENT CONFIG ==================='
            Add-Content -Path $LogFilePath -Value $cfg
        }
    }
    catch {
        Write-Status 'Config list' "Failed: $($_.Exception.Message)" Yellow
    }

    try {
        $services = Get-Service himds, GCArcService, ExtensionService -ErrorAction SilentlyContinue
        if ($services) {
            foreach ($svc in $services) {
                $color = if ($svc.Status -eq 'Running') { 'Green' } elseif ($svc.Status -eq 'Stopped') { 'Yellow' } else { 'DarkYellow' }
                Write-Status ("svc/$($svc.Name)") ("$($svc.Status) | StartType=$($svc.StartType)") $color
                if ($svc.Status -ne 'Running') {
                    Add-Issue -Severity 'HIGH' -Category 'AgentService' -Message "Service $($svc.Name) is $($svc.Status)" -Fix 'Start or restart the service and re-run the check.'
                }
            }
        }
    }
    catch {
        Write-Status 'Services' "Failed: $($_.Exception.Message)" Yellow
    }

    $himdsLog = Join-Path $env:ProgramData 'AzureConnectedMachineAgent\Log\himds.log'
    if (Test-Path $himdsLog) {
        Write-Status 'himds.log' $himdsLog DarkGray
        Add-Content -Path $LogFilePath -Value ''
        Add-Content -Path $LogFilePath -Value '=================== HIMDS LOG TAIL ==================='
        try {
            Get-Content -Path $himdsLog -Tail 20 | Add-Content -Path $LogFilePath
        }
        catch {
            Add-Content -Path $LogFilePath -Value "Could not read himds.log: $($_.Exception.Message)"
        }
    }
}

function Detect-Platform {
    param()

    if ($Platform -ne 'Auto') {
        return $Platform
    }

    try {
        $resp = Invoke-RestMethod -Uri 'http://169.254.169.253:80/metadata/attested/document?api-version=2018-10-01' -Headers @{ Metadata = 'true' } -TimeoutSec 3 -ErrorAction Stop
        if ($resp) { return 'AzureLocal' }
    }
    catch { }

    try {
        $resp = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' -Headers @{ Metadata = 'true' } -TimeoutSec 3 -ErrorAction Stop
        if ($resp) { return 'AzureVM' }
    }
    catch { }

    return 'Arc'
}

function Run-PlatformChecks {
    param([string]$DetectedPlatform)

    Write-Section 'Platform Checks'
    Write-Status 'Platform' $DetectedPlatform White

    switch ($DetectedPlatform) {
        'AzureLocal' {
            try {
                $att = Invoke-RestMethod -Uri 'http://169.254.169.253:80/metadata/attested/document?api-version=2018-10-01' -Headers @{ Metadata = 'true' } -TimeoutSec 5 -ErrorAction Stop
                Write-Status 'Azure Local IMDS' 'Attestation endpoint reachable' Green
                Log 'Azure Local attestation endpoint reachable' 'OK'
            }
            catch {
                Write-Status 'Azure Local IMDS' "Failed: $($_.Exception.Message)" Yellow
                Add-Issue -Severity 'WARN' -Category 'AzureLocal' -Message 'Azure Local attestation endpoint not reachable.' -Fix 'Validate Azure Local guest metadata routing if this machine is expected to run on Azure Local.'
            }
        }
        'AzureStackHub' {
            try {
                $ws = Invoke-RestMethod -Uri 'http://168.63.129.16/?comp=versions' -Method Get -TimeoutSec 5 -ErrorAction Stop
                if ($ws) {
                    Write-Status 'WireServer' 'Reachable' Green
                    Log 'WireServer reachable' 'OK'
                }
            }
            catch {
                Write-Status 'WireServer' "Failed: $($_.Exception.Message)" Yellow
                Add-Issue -Severity 'WARN' -Category 'AzureStackHub' -Message 'WireServer not reachable from guest.' -Fix 'Validate host-agent / guest networking if this guest is expected to be on Azure Stack Hub.'
            }
        }
        'AzureVM' {
            try {
                $imds = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/instance?api-version=2021-02-01' -Headers @{ Metadata = 'true' } -TimeoutSec 5 -ErrorAction Stop
                if ($imds) {
                    Write-Status 'IMDS' 'Reachable' Green
                    Log 'Azure VM IMDS reachable' 'OK'
                }
            }
            catch {
                Write-Status 'IMDS' "Failed: $($_.Exception.Message)" Yellow
                Add-Issue -Severity 'WARN' -Category 'AzureVM' -Message 'IMDS not reachable.' -Fix 'Validate guest routing and local metadata access if this is expected to be an Azure VM.'
            }
        }
        default {
            Write-Status 'Platform extras' 'No platform-specific metadata probe required' DarkGray
        }
    }
}

Write-Banner 'AZURE ARC ENDPOINT CHECK (REVISED)'
Write-Status 'Host' $env:COMPUTERNAME
Write-Status 'Time' (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

$azcm = Get-AzcmagentPath
$script:PreOnboarding = (-not $azcm)
if ($azcm) {
    try {
        $json = & $azcm show -j 2>$null | Out-String
        if ($json) {
            $script:AgentJson = $json | ConvertFrom-Json
            Add-Content -Path $LogFilePath -Value ''
            Add-Content -Path $LogFilePath -Value '=================== AGENT SHOW JSON ==================='
            Add-Content -Path $LogFilePath -Value $json
        }
    }
    catch {
        Log "Could not parse azcmagent show -j: $($_.Exception.Message)" 'WARN'
    }
}

if (-not $script:PreOnboarding -and $script:AgentJson) {
    $agentStatus = if ($script:AgentJson.PSObject.Properties['status']) { [string]$script:AgentJson.status } else { '' }
    $agentResourceId = $null
    foreach ($propName in @('resourceId', 'id')) {
        if ($script:AgentJson.PSObject.Properties[$propName]) {
            $candidateValue = [string]$script:AgentJson.$propName
            if (-not [string]::IsNullOrWhiteSpace($candidateValue)) {
                $agentResourceId = $candidateValue
                break
            }
        }
    }

    $agentLooksOnboarded = (($agentStatus -in @('Connected', 'Disconnected')) -or -not [string]::IsNullOrWhiteSpace($agentResourceId))
    $script:PreOnboarding = (-not $agentLooksOnboarded)
}

if ($azcm -and $script:AgentJson) {
    $statusParts = @('Installed')
    if ($script:AgentJson.status) { $statusParts += $script:AgentJson.status }
    if ($script:AgentJson.agentVersion) { $statusParts += "v$($script:AgentJson.agentVersion)" }
    Write-Status 'Agent' ($statusParts -join ' | ') $(if ($script:AgentJson.status -eq 'Connected') { 'Green' } elseif ($script:AgentJson.status -eq 'Disconnected') { 'Red' } else { 'Yellow' })
}
elseif ($azcm) {
    Write-Status 'Agent' 'Installed (status unavailable)' Yellow
}
else {
    Write-Status 'Agent' 'NOT INSTALLED (pre-onboarding mode)' Yellow
}

if (-not $SkipAgentHealth) {
    Get-AgentHealth -AzcmPath $azcm
}

$detectedPlatform = Detect-Platform
Write-Status 'Detected platform' $detectedPlatform DarkGray
if ($Platform -eq 'Auto') { $Platform = $detectedPlatform }
Write-Status 'Platform in use' $Platform White

if (-not $Region) {
    if ($script:AgentJson -and $script:AgentJson.location) {
        $Region = $script:AgentJson.location
        Write-Status 'Region' "$Region (auto-detected)" Green
    }
    else {
        $Region = 'eastus2'
        Write-Status 'Region' "$Region (default fallback)" Yellow
        Add-Issue -Severity 'WARN' -Category 'Region' -Message 'Region could not be auto-detected; using eastus2 fallback.' -Fix 'Specify -Region explicitly for pre-onboarding or disconnected scenarios.'
    }
}
else {
    Write-Status 'Region' "$Region (specified)" White
}

if ($Mode -eq 'Auto') {
    if ($script:AgentJson) {
        $gwUrl = $null
        if ($script:AgentJson.PSObject.Properties['gatewayUrl']) { $gwUrl = $script:AgentJson.gatewayUrl }
        elseif ($script:AgentJson.PSObject.Properties['gatewayurl']) { $gwUrl = $script:AgentJson.gatewayurl }

        $privateLinkScope = $null
        if ($script:AgentJson.PSObject.Properties['privateLinkScope']) { $privateLinkScope = $script:AgentJson.privateLinkScope }
        elseif ($script:AgentJson.PSObject.Properties['privatelinkscope']) { $privateLinkScope = $script:AgentJson.privatelinkscope }

        if ($gwUrl) {
            $Mode = 'Gateway'
            $script:GatewayUrl = $gwUrl
        }
        elseif ($privateLinkScope) {
            $Mode = 'Private'
        }
        else {
            try {
                $dnsLookup = Resolve-Endpoint -Endpoint 'gbl.his.arc.azure.com'
                if ($dnsLookup.Error) { throw $dnsLookup.Error }
                $ip = ($dnsLookup.Result | Where-Object { $_.Type -eq 'A' -and $_.IPAddress } | Select-Object -First 1).IPAddress
                $Mode = if (Test-IsPrivateIp -Ip $ip) { 'Private' } else { 'Public' }
            }
            catch {
                $Mode = 'Public'
            }
        }
    }
    else {
        $Mode = 'Public'
    }
}
Write-Status 'Mode' $Mode $(switch ($Mode) { 'Private' { 'Magenta' } 'Gateway' { 'DarkYellow' } default { 'Green' } })

Write-Section 'Proxy Configuration'

try {
    $wh = netsh winhttp show proxy 2>$null | Out-String
    if ($wh -match 'Proxy Server\(s\)\s*:\s*(.+)|Servidor\(es\) Proxy\s*:\s*(.+)') {
        $script:WinHttpProxy = ($Matches[1], $Matches[2] | Where-Object { $_ } | Select-Object -First 1).Trim()
    }
    if (-not $script:WinHttpProxy -and $wh -notmatch 'Direct|direct|Direto|direto|Direkt' -and $wh -match '(https?://[^\s;]+)') {
        $script:WinHttpProxy = $Matches[1].Trim()
    }
    if ($wh -match 'Bypass List\s*:\s*(.+)|Lista de bypass\s*:\s*(.+)') {
        $script:WinHttpBypass = ($Matches[1], $Matches[2] | Where-Object { $_ } | Select-Object -First 1).Trim()
    }
}
catch { }

$agentProxy = $null
$agentRuntimeProxy = $null
$agentUpstreamProxy = $null
$agentBypass = $null
$hasAgentBypass = $false
if ($azcm) {
    try {
        $rawProxy = (& $azcm config get proxy.url 2>$null | Out-String).Trim()
        if (Test-IsValidProxyUri $rawProxy) { $agentProxy = $rawProxy }
        $agentBypass = (& $azcm config get proxy.bypass 2>$null | Out-String).Trim()
        if ($agentBypass -and $agentBypass -notmatch '^\[\s*\]$') {
            $hasAgentBypass = $true
        }
    }
    catch { }
}
if ($script:AgentJson) {
    if ($script:AgentJson.PSObject.Properties['httpsProxy']) {
        $runtimeProxyCandidate = [string]$script:AgentJson.httpsProxy
        if (Test-IsValidProxyUri $runtimeProxyCandidate) { $agentRuntimeProxy = $runtimeProxyCandidate }
    }
    if ($script:AgentJson.PSObject.Properties['upstreamProxy']) {
        $upstreamProxyCandidate = [string]$script:AgentJson.upstreamProxy
        if (Test-IsValidProxyUri $upstreamProxyCandidate) { $agentUpstreamProxy = $upstreamProxyCandidate }
    }
}

$envProxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Machine')
if (-not $envProxy) { $envProxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process') }
$envNoProxy = [Environment]::GetEnvironmentVariable('NO_PROXY', 'Machine')
if (-not $envNoProxy) { $envNoProxy = [Environment]::GetEnvironmentVariable('NO_PROXY', 'Process') }

if ($ProxyUrl -and (Test-IsValidProxyUri $ProxyUrl)) {
    $script:EffectiveProxy = $ProxyUrl
}
elseif ($agentRuntimeProxy) {
    $script:EffectiveProxy = $agentRuntimeProxy
}
elseif ($agentProxy) {
    $script:EffectiveProxy = $agentProxy
}
elseif ($envProxy -and (Test-IsValidProxyUri $envProxy)) {
    $script:EffectiveProxy = $envProxy
}

$script:ProxyMode = if ($script:EffectiveProxy) { 'ExplicitProxy' } else { 'Direct' }

$pFmt = "  {0,-18} | {1,-35} | {2,-22}"
Write-Host ($pFmt -f 'Source', 'Proxy', 'Used By') -ForegroundColor Cyan
Write-Host ("  {0,-18}-+-{1,-35}-+-{2,-22}" -f ('-' * 18), ('-' * 35), ('-' * 22)) -ForegroundColor DarkGray
foreach ($row in @(
    @('WinHTTP (OS)', $(if ($script:WinHttpProxy) { $script:WinHttpProxy } else { 'Direct' }), 'SCHANNEL/OCSP/CRL'),
    @('azcmagent rt', $(if ($agentRuntimeProxy) { $agentRuntimeProxy } else { '(not set)' }), 'Arc runtime path'),
    @('azcmagent cfg', $(if ($agentProxy) { $agentProxy } else { '(not set)' }), 'Configured upstream'),
    @('upstreamProxy', $(if ($agentUpstreamProxy) { $agentUpstreamProxy } else { '(not set)' }), 'Gateway upstream'),
    @('HTTPS_PROXY', $(if ($envProxy) { $envProxy } else { '(not set)' }), 'Extensions')
)) {
    $color = if ($row[1] -match 'Direct|not set') { 'DarkGray' } else { 'White' }
    Write-Host ($pFmt -f $row[0], $row[1], $row[2]) -ForegroundColor $color
}
Write-Status 'Effective proxy' $(if ($script:EffectiveProxy) { $script:EffectiveProxy } else { 'Direct' }) $(if ($script:EffectiveProxy) { 'Green' } else { 'DarkGray' })
Write-Status 'Proxy mode' $script:ProxyMode $(if ($script:ProxyMode -eq 'ExplicitProxy') { 'Green' } else { 'DarkGray' })

if ($Mode -eq 'Gateway' -and $hasAgentBypass) {
    Write-Status 'Gateway bypass' 'Configured categories present, but Arc Gateway does not support proxy bypass' Yellow
    Add-Issue -Severity 'INFO' -Category 'Gateway' -Message 'proxy.bypass is configured, but Azure Arc Gateway does not support proxy bypass. Treat bypass settings as non-effective for the Arc agent path in gateway mode.' -Fix 'Validate the gateway path without relying on proxy bypass semantics.'
}

if ($script:EffectiveProxy) {
    try {
        $pxUri = [System.Uri]$script:EffectiveProxy
        $script:EffectiveProxyReachable = Test-TcpPort -HostName $pxUri.Host -Port $pxUri.Port -TimeoutMs 4000
        Write-Status 'Proxy reachability' ("$($pxUri.Host):$($pxUri.Port) => " + $(if ($script:EffectiveProxyReachable) { 'Reachable' } else { 'Unreachable' })) $(if ($script:EffectiveProxyReachable) { 'Green' } else { 'Red' })
    }
    catch {
        $script:EffectiveProxyParseError = $_.Exception.Message
        Add-Issue -Severity 'HIGH' -Category 'Proxy' -Message 'Effective proxy URI is not parseable.' -Fix 'Validate -ProxyUrl or local proxy configuration.'
    }
}

Write-Section 'TLS Validation'
$handshakeOk = $false
$tls12Disabled = $false
$cipherWarning = $false
$cipherInventorySupported = $false
$cipherInventoryError = $null
$strongCrypto = $false
$legacyTls12OnlyOs = $false
try {
    $os = Get-OperatingSystemInfo
    $osCaption = if ($os -and $os.Caption) { $os.Caption } else { "Windows $([System.Environment]::OSVersion.Version)" }
    $legacyTls12OnlyOs = Test-IsLegacyTls12OnlyOs -OsInfo $os
    Write-Status 'OS' $osCaption DarkGray
    if ($legacyTls12OnlyOs) {
        Write-Status 'TLS posture' 'Legacy OS detected; TLS 1.2 is the required baseline and TLS 1.3 observations are informational.' DarkGray
    }

    $schBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
    $tls12Path = "$schBase\TLS 1.2\Client"
    if (Test-Path $tls12Path) {
        $enabled = (Get-ItemProperty -Path $tls12Path -Name 'Enabled' -ErrorAction SilentlyContinue).Enabled
        $disabledByDefault = (Get-ItemProperty -Path $tls12Path -Name 'DisabledByDefault' -ErrorAction SilentlyContinue).DisabledByDefault
        if ($enabled -eq 0 -or ($disabledByDefault -eq 1 -and $enabled -ne 1)) {
            $tls12Disabled = $true
        }
    }

    $savedProto = [System.Net.ServicePointManager]::SecurityProtocol
    $tlsProbeEndpoint = 'login.microsoftonline.com'
    $tlsProbeBypassed = $false
    $tlsUsesProxy = $false
    $tlsBypassedEndpoints = Get-AgentBypassedEndpoints -AgentBypass $agentBypass -Region $Region
    foreach ($entry in $tlsBypassedEndpoints) {
        if (-not $entry) { continue }
        $norm = $entry.Trim().ToLower()
        if (-not $norm) { continue }
        if ($norm.StartsWith('*.')) { $norm = $norm.Substring(1) }
        $probeHost = $tlsProbeEndpoint.Trim().ToLower()
        if ($probeHost -eq $norm.TrimStart('.') -or ($norm.StartsWith('.') -and $probeHost.EndsWith($norm))) {
            $tlsProbeBypassed = $true
            break
        }
    }
    if ($tlsProbeBypassed) {
        Write-Status 'TLS probe path' 'AAD bypass applied; probing direct path to login.microsoftonline.com' DarkGray
    }
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $request = [System.Net.HttpWebRequest]::Create("https://$tlsProbeEndpoint")
        $request.Method = 'HEAD'
        $request.Timeout = 10000
        if ($script:EffectiveProxy -and -not $tlsProbeBypassed) {
            $request.Proxy = New-Object System.Net.WebProxy($script:EffectiveProxy)
            $request.Proxy.UseDefaultCredentials = $true
            $tlsUsesProxy = $true
        }
        else {
            $request.Proxy = $null
        }
        $response = $request.GetResponse()
        $response.Close()
        $handshakeOk = $true
    }
    catch {
        $handshakeOk = $false
    }
    finally {
        [System.Net.ServicePointManager]::SecurityProtocol = $savedProto
    }

    foreach ($regPath in 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319') {
        if (Test-Path $regPath) {
            $sc = (Get-ItemProperty -Path $regPath -Name 'SchUseStrongCrypto' -ErrorAction SilentlyContinue).SchUseStrongCrypto
            if ($sc -eq 1) { $strongCrypto = $true }
        }
    }

    $requiredGcm = @(
        'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384',
        'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
    )
    $cipherInventory = Get-TlsCipherInventory
    $cipherInventorySupported = $cipherInventory.Supported
    $cipherInventoryError = $cipherInventory.Error
    if ($cipherInventorySupported -and $cipherInventory.Names.Count -gt 0) {
        foreach ($cipher in $requiredGcm) {
            if ($cipherInventory.Names -notcontains $cipher) {
                $cipherWarning = $true
                break
            }
        }
    }

    if ($tls12Disabled) {
        Write-Status 'TLS 1.2' 'Disabled in SCHANNEL' Red
        Add-Issue -Severity 'CRITICAL' -Category 'TLS' -Message 'TLS 1.2 is disabled in SCHANNEL.' -Fix 'Enable TLS 1.2 in SCHANNEL and re-run the check.'
    }
    elseif ($handshakeOk) {
        Write-Status 'TLS handshake' 'TLS 1.2 handshake succeeded' Green
    }
    else {
        $tlsMessage = 'Live TLS 1.2 handshake to login.microsoftonline.com failed.'
        $tlsFix = 'Validate outbound TLS inspection, proxy behavior, SCHANNEL policy, and root trust.'
        $tlsSeverity = 'HIGH'
        if ($tlsUsesProxy) {
            $tlsSeverity = 'WARN'
            $tlsMessage = 'Live TLS 1.2 handshake failed through the configured proxy path.'
            $tlsFix = 'Validate proxy CONNECT policy or TLS inspection before treating this as an OS TLS problem.'
        }
        elseif ($legacyTls12OnlyOs) {
            $tlsSeverity = 'WARN'
            $tlsMessage = 'Live TLS 1.2 handshake failed on a legacy TLS-1.2-only OS.'
            $tlsFix = 'If azcmagent still reports core healthy, treat this as an inspection/path warning and validate SCHANNEL, root trust, and outbound filtering.'
        }

        Write-Status 'TLS handshake' 'Live TLS 1.2 handshake failed' Yellow
        $script:DeferredTlsIssue = [pscustomobject]@{
            Severity = $tlsSeverity
            Message = $tlsMessage
            Fix = $tlsFix
            UsesProxy = $tlsUsesProxy
        }
    }

    if (-not $cipherInventorySupported) {
        Write-Status 'Cipher suites' 'Local cipher inventory unavailable on this PowerShell/OS; skipped' DarkGray
    }
    elseif ($cipherWarning) {
        Write-Status 'Cipher suites' 'GCM suite set appears reduced' Yellow
        Add-Issue -Severity 'WARN' -Category 'TLS Ciphers' -Message 'Expected GCM cipher suites were not fully observed in the local inventory.' -Fix 'Review local cipher policy if Arc TLS negotiation still fails.'
    }
    else {
        Write-Status 'Cipher suites' 'No blocking issue detected' Green
    }

    Write-Status '.NET StrongCrypto' $(if ($strongCrypto) { 'Enabled' } else { 'Not set' }) $(if ($strongCrypto) { 'Green' } else { 'Yellow' })
}
catch {
    Write-Status 'TLS' "Validation error: $($_.Exception.Message)" Yellow
    Add-Issue -Severity 'WARN' -Category 'TLS' -Message 'TLS validation encountered an error.' -Fix 'Review PowerShell / .NET capabilities on this OS and validate TLS manually if needed.'
}

if (-not $SkipExtensions -and $azcm) {
    try {
        $extOut = & $azcm extension list 2>$null | Out-String
        if ($extOut) {
            if ($extOut -match 'WindowsAgent\.SqlServer|LinuxAgent\.SqlServer|SqlServer') { $script:InstalledExts += 'SQL' }
            if ($extOut -match 'AzureMonitor|AMA') { $script:InstalledExts += 'AMA' }
            if ($extOut -match 'MDE|DefenderForServers|AzureDefender') { $script:InstalledExts += 'MDE' }
            if ($extOut -match 'AdminCenter') { $script:InstalledExts += 'WAC' }
            if ($extOut -match 'KeyVault') { $script:InstalledExts += 'KV' }
            if ($extOut -match 'HybridWorker|Automation') { $script:InstalledExts += 'HRW' }
            if ($extOut -match 'ChangeTracking') { $script:InstalledExts += 'CT' }
            if ($extOut -match 'GuestAttestation|WindowsAttestation|LinuxAttestation') { $script:InstalledExts += 'GA' }
            if ($extOut -match 'WindowsPatchExtension|LinuxPatchExtension|UpdateManagement') { $script:InstalledExts += 'UM' }
            if ($extOut -match 'CustomScript') { $script:InstalledExts += 'CS' }
            if ($extOut -match 'DependencyAgent') { $script:InstalledExts += 'DA' }
            if ($extOut -match 'DefenderForSQL|AdvancedThreatProtection|MicrosoftDefenderForSQL') { $script:InstalledExts += 'DSQL' }
            $script:InstalledExts = $script:InstalledExts | Select-Object -Unique
        }
    }
    catch {
        Add-Issue -Severity 'WARN' -Category 'Extensions' -Message 'Could not enumerate installed Arc extensions.' -Fix 'Verify azcmagent extension list output on this agent version.'
    }
}
Write-Status 'Extensions' $(if ($script:InstalledExts.Count -gt 0) { $script:InstalledExts -join ', ' } elseif ($CheckIncludeAll) { 'all (forced)' } else { '(none detected)' }) $(if ($script:InstalledExts.Count -gt 0) { 'White' } else { 'DarkGray' })

$pkiEndpoints = @(
    'oneocsp.microsoft.com',
    'ocsp.msocsp.com',
    'crl.microsoft.com',
    'crl2.microsoft.com',
    'crl3.microsoft.com',
    'crl4.microsoft.com',
    'crl3.digicert.com',
    'crl4.digicert.com',
    'ocsp.digicert.com',
    'ctldl.windowsupdate.com',
    'www.microsoft.com',
    'caissuers.microsoft.com',
    'login.live.com'
)

function Get-PkiBypassEntries {
    $bypassEntries = @()
    if ($script:WinHttpBypass) {
        $bypassEntries += $script:WinHttpBypass -split ';' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
    }
    if ($envNoProxy) {
        $bypassEntries += $envNoProxy -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
    }
    return @($bypassEntries | Select-Object -Unique)
}

function Test-IsPkiCoveredByBypassOnly {
    param([string]$Endpoint)

    $endpointHost = $Endpoint.Trim().ToLower()
    foreach ($entry in (Get-PkiBypassEntries)) {
        if (-not $entry) { continue }
        $norm = $entry.Trim().ToLower()
        if (-not $norm) { continue }
        if ($norm.StartsWith('*.')) { $norm = $norm.Substring(1) }
        if ($endpointHost -eq $norm.TrimStart('.') -or ($norm.StartsWith('.') -and $endpointHost.EndsWith($norm))) {
            return $true
        }
    }
    return $false
}

function Get-PkiBypassGaps {
    if (-not $script:WinHttpProxy) { return @() }

    $bypassEntries = Get-PkiBypassEntries
    if ($bypassEntries.Count -eq 0) { return $pkiEndpoints }

    $missing = @()
    foreach ($ep in $pkiEndpoints) {
        $covered = $false
        $endpointHost = $ep.Trim().ToLower()
        foreach ($entry in $bypassEntries) {
            if (-not $entry) { continue }
            $norm = $entry.Trim().ToLower()
            if (-not $norm) { continue }
            if ($norm.StartsWith('*.')) { $norm = $norm.Substring(1) }
            if ($endpointHost -eq $norm.TrimStart('.') -or ($norm.StartsWith('.') -and $endpointHost.EndsWith($norm))) {
                $covered = $true
                break
            }
        }
        if (-not $covered) { $missing += $ep }
    }
    return $missing
}

if (-not $SkipPKI -and $script:WinHttpProxy) {
    Write-Section 'PKI / OCSP / CRL Bypass'
    $missingPki = Get-PkiBypassGaps
    if ($missingPki.Count -eq 0) {
        Write-Status 'PKI bypass' 'Coverage looks reasonable via local bypass settings' Green
    }
    else {
        Write-Status 'PKI bypass' ("Local bypass coverage is incomplete: $($missingPki -join ', ')") Yellow
        Add-Issue -Severity 'INFO' -Category 'PKI Coverage' -Message 'Some PKI endpoints are not covered by local bypass configuration (WinHTTP bypass / NO_PROXY). Treat this as inventory only; it is not causal evidence of failure for this run.' -Fix 'Correlate with observed HTTP/TLS probe errors before changing proxy, firewall, route, or PKI policy.'
    }
}

Write-Section 'Endpoint Discovery (azcmagent check)'
$coreEndpoints = [System.Collections.ArrayList]@(
    'login.windows.net',
    'login.microsoftonline.com',
    "$Region.login.microsoft.com",
    'pas.windows.net',
    'gbl.his.arc.azure.com',
    'agentserviceapi.guestconfiguration.azure.com'
)
$controlPlaneEndpoints = [System.Collections.ArrayList]@(
    'management.azure.com'
)
$lifecycleEndpoints = [System.Collections.ArrayList]@(
    'packages.microsoft.com',
    'download.microsoft.com'
)
$privateEligible = [System.Collections.ArrayList]@(
    'gbl.his.arc.azure.com',
    'agentserviceapi.guestconfiguration.azure.com',
    'global.handler.control.monitor.azure.com'
)

if ($Mode -in @('Public', 'Gateway')) {
    [void]$coreEndpoints.Add('guestnotificationservice.azure.com')
}

if ($script:AgentJson) {
    $gw = $null
    if ($script:AgentJson.PSObject.Properties['gatewayUrl']) { $gw = $script:AgentJson.gatewayUrl }
    elseif ($script:AgentJson.PSObject.Properties['gatewayurl']) { $gw = $script:AgentJson.gatewayurl }
    if ($gw) {
        $script:GatewayUrl = $gw
        try {
            $gwHost = ([System.Uri]$gw).Host
            if ($gwHost -and $coreEndpoints -notcontains $gwHost) { [void]$coreEndpoints.Add($gwHost) }
        }
        catch { }
    }
}

$extEndpoints = @{}
if ($script:InstalledExts -contains 'SQL' -or $CheckIncludeAll) {
    $extEndpoints['SQL'] = @(
        "dataprocessingservice.$Region.arcdataservices.com",
        "telemetry.$Region.arcdataservices.com",
        "san-af-$Region-prod.azurewebsites.net",
        'graph.microsoft.com',
        'dc.services.visualstudio.com'
    )
}
if ($script:InstalledExts -contains 'DSQL' -or $CheckIncludeAll) {
    if (-not $extEndpoints.ContainsKey('SQL')) { $extEndpoints['SQL'] = @() }
    $extEndpoints['SQL'] += "defender-for-databases.$Region.arcdataservices.com"
}
if ($script:InstalledExts -contains 'AMA' -or $script:InstalledExts -contains 'DA' -or $CheckIncludeAll) {
    $extEndpoints['AMA'] = @(
        'global.handler.control.monitor.azure.com',
        'global.prod.microsoftmetrics.com',
        "$Region.handler.control.monitor.azure.com",
        "$Region.monitoring.azure.com"
    )
}
if ($script:InstalledExts -contains 'MDE' -or $CheckIncludeAll) {
    $extEndpoints['MDE'] = @(
        'unitedstates.x.cp.wd.microsoft.com',
        'us-v20.events.data.microsoft.com',
        'winatp-gw-cus3.microsoft.com'
    )
}
if ($script:InstalledExts -contains 'WAC' -or $CheckIncludeAll) {
    $extEndpoints['WAC'] = @("$Region.service.waconazure.com")
}
if ($script:InstalledExts -contains 'KV' -or $CheckIncludeAll) {
    $extEndpoints['KV'] = @('*.vault.azure.net')
}
if ($script:InstalledExts -contains 'HRW' -or $CheckIncludeAll) {
    $extEndpoints['HRW'] = @('*.azure-automation.net', '*.agentsvc.azure-automation.net')
}
if ($script:InstalledExts -contains 'UM' -or $CheckIncludeAll) {
    $extEndpoints['UM'] = @("$Region.monitoring.azure.com")
}
if ($script:InstalledExts -contains 'GA' -or $CheckIncludeAll) {
    $extEndpoints['GA'] = @('*.attest.azure.net')
}
if ($SkipExtensions) { $extEndpoints = @{} }

$discoveredEndpoints = @()
if ($azcm) {
    $checkArgs = @('check', '--location', $Region, '--cloud', 'AzureCloud', '--verbose')
    if ($CheckIncludeAll) {
        $checkArgs += @('--extensions', 'all', '--include-all')
    }
    elseif ($script:InstalledExts -contains 'SQL') {
        $checkArgs += @('--extensions', 'sql')
    }
    if ($Mode -eq 'Private') {
        $checkArgs += '--enable-pls-check'
    }

    Write-Host "  azcmagent $($checkArgs -join ' ')" -ForegroundColor Gray
    try {
        $checkOut = & $azcm @checkArgs 2>&1
        $script:AzcmagentCheckExit = $LASTEXITCODE
        Add-Content -Path $LogFilePath -Value ''
        Add-Content -Path $LogFilePath -Value '=================== AZCMAGENT CHECK ==================='
        Add-Content -Path $LogFilePath -Value $checkOut

        foreach ($line in $checkOut) {
            $s = "$line".Trim()
            if ($s -match '\|\s*https?://([^\s|/]+)') {
                $fqdn = $Matches[1]
                if ($fqdn -and $fqdn -notmatch '^(Use Case|Endpoint)$') {
                    $discoveredEndpoints += $fqdn
                }
            }

            if ($s -match 'Endpoint properties\s+(.+)$') {
                $payload = $Matches[1]
                $hostName = $null
                $useCase = $null
                $reachable = $null
                $proxyStatus = $null
                $private = $null
                $tls = $null

                if ($payload -match 'hostname=([^\s]+)') { $hostName = $Matches[1] }
                if ($payload -match 'useCase=([^\s]+)') { $useCase = $Matches[1] }
                if ($payload -match 'reachable=(true|false)') { $reachable = ($Matches[1] -eq 'true') }
                if ($payload -match 'proxyStatus=("[^"]+"|[^\s]+)') { $proxyStatus = $Matches[1].Trim('"') }
                if ($payload -match 'private=(true|false|unknown)') { $private = $Matches[1] }
                if ($payload -match 'tls=("[^"]+"|[^\s]+)') { $tls = $Matches[1].Trim('"') }

                if ($hostName) {
                    $script:AzcmagentEndpointMeta[$hostName] = [pscustomobject]@{
                        HostName = $hostName
                        UseCase = $useCase
                        Group = Convert-AzcmagentUseCaseToGroup -UseCase $useCase
                        Reachable = $reachable
                        ProxyStatus = $proxyStatus
                        Private = $private
                        Tls = $tls
                    }
                }
            }

            if ($s -match 'Check result\s+check_name="[^"]+"\s+endpoint="https?://([^"]+)".*status=(failureed|failed|failure)') {
                $failedEndpoint = $Matches[1]
                if ($failedEndpoint -and $script:AzcmagentFailedEndpoints -notcontains $failedEndpoint) {
                    [void]$script:AzcmagentFailedEndpoints.Add($failedEndpoint)
                }
            }

            if ($s -match 'checks_failed=(\d+)') {
                $script:AzcmagentChecksFailed = [int]$Matches[1]
            }
            if ($s -match 'critical_failures=(\d+)') {
                $script:AzcmagentCriticalFailures = [int]$Matches[1]
            }
            if ($s -match 'All endpoints needed to connect to Azure are available\.') {
                $script:AzcmagentCoreHealthy = $true
            }
        }
        $discoveredEndpoints = $discoveredEndpoints | Select-Object -Unique
        $summary = "exit $($script:AzcmagentCheckExit); discovered $($discoveredEndpoints.Count) endpoints"
        if ($null -ne $script:AzcmagentChecksFailed) {
            $summary += "; checks_failed=$($script:AzcmagentChecksFailed)"
        }
        if ($null -ne $script:AzcmagentCriticalFailures) {
            $summary += "; critical_failures=$($script:AzcmagentCriticalFailures)"
        }
        Write-Status 'azcmagent check' $summary $(if ($script:AzcmagentCheckExit -eq 0) { 'Green' } else { 'Yellow' })
        if ($script:AzcmagentCheckExit -ne 0 -and (($null -eq $script:AzcmagentCriticalFailures) -or $script:AzcmagentCriticalFailures -gt 0)) {
            $failedCoreDetail = ''
            if ($script:AzcmagentFailedEndpoints.Count -gt 0) {
                $failedCoreDetail = ' Failed required endpoint(s): ' + (($script:AzcmagentFailedEndpoints | Select-Object -Unique) -join ', ') + '.'
            }
            Add-Issue -Severity 'HIGH' -Category 'Core Connectivity' -Message ("azcmagent reported required Arc connectivity failures." + $failedCoreDetail) -Fix 'Review the failed required endpoint(s), gateway/proxy path, and azcmagent check section in the log file.'
        }
    }
    catch {
        Write-Status 'azcmagent check' "Failed: $($_.Exception.Message)" Yellow
        Add-Issue -Severity 'HIGH' -Category 'AgentCheck' -Message 'azcmagent check could not be executed.' -Fix 'Validate azcmagent installation and command availability.'
    }
}
else {
    Write-Status 'azcmagent check' 'Skipped - azcmagent not installed' Yellow
}

foreach ($ep in $discoveredEndpoints) {
    if ($coreEndpoints -notcontains $ep) { [void]$coreEndpoints.Add($ep) }
    if ($ep -match 'his\.arc\.azure\.com|guestconfiguration\.azure\.com') {
        if ($privateEligible -notcontains $ep) { [void]$privateEligible.Add($ep) }
    }
}

$script:AzcmagentPrivatePathHealthy = (@(
    $script:AzcmagentEndpointMeta.Values | Where-Object {
        $_.Reachable -eq $true -and ($privateEligible -contains $_.HostName) -and (
            $_.Private -eq 'true' -or
            ($_.ProxyStatus -eq 'bypassed' -and $_.HostName -match 'his\.arc\.azure\.com|guestconfiguration\.azure\.com')
        )
    }
).Count -gt 0)

if ($script:EffectiveProxy -and $script:EffectiveProxyParseError -eq $null -and $script:EffectiveProxyReachable -eq $false) {
    $pxUri = [System.Uri]$script:EffectiveProxy
    $proxyCoreHealthyNoCritical = (($script:AzcmagentCoreHealthy -eq $true) -or (($null -ne $script:AzcmagentCriticalFailures) -and $script:AzcmagentCriticalFailures -eq 0))
    $proxyPrivatePathHealthyObserved = (
        $script:AzcmagentPrivatePathHealthy -or
        @(
            $script:AzcmagentEndpointMeta.Values | Where-Object {
                $_.Reachable -eq $true -and ($privateEligible -contains $_.HostName) -and (
                    $_.Private -eq 'true' -or
                    ($_.ProxyStatus -eq 'bypassed' -and $_.HostName -match 'his\.arc\.azure\.com|guestconfiguration\.azure\.com')
                )
            }
        ).Count -gt 0
    )

    if ($Mode -eq 'Private' -and $proxyCoreHealthyNoCritical -and $proxyPrivatePathHealthyObserved) {
        Add-Issue -Severity 'WARN' -Category 'Proxy' -Message "Configured proxy $($pxUri.Host):$($pxUri.Port) is not reachable. In Private/split-network mode this is treated as a non-blocking proxy-path warning because Arc private-capable endpoints remained healthy." -Fix 'Validate proxy host, port, routing, and firewall if ARM control-plane or other proxy-routed endpoints are in scope.'
    }
    else {
        Add-Issue -Severity 'CRITICAL' -Category 'Proxy' -Message "Configured proxy $($pxUri.Host):$($pxUri.Port) is not reachable." -Fix 'Validate proxy host, port, routing, and firewall.'
    }
}

if ($script:DeferredTlsIssue) {
    $tlsCoreHealthyNoCritical = (($script:AzcmagentCoreHealthy -eq $true) -or (($null -ne $script:AzcmagentCriticalFailures) -and $script:AzcmagentCriticalFailures -eq 0))
    if ($script:DeferredTlsIssue.UsesProxy -and $tlsCoreHealthyNoCritical) {
        Write-Status 'TLS interpretation' 'Proxy-path TLS probe failed, but azcmagent reported core connectivity healthy' DarkGray
    }
    else {
        Add-Issue -Severity $script:DeferredTlsIssue.Severity -Category 'TLS' -Message $script:DeferredTlsIssue.Message -Fix $script:DeferredTlsIssue.Fix
    }
}

$endpointGroupMap = @{}
foreach ($ep in $coreEndpoints) {
    $endpointGroupMap[$ep] = if ($script:AzcmagentEndpointMeta.ContainsKey($ep)) { $script:AzcmagentEndpointMeta[$ep].Group } else { 'Core' }
}
foreach ($ep in $controlPlaneEndpoints) {
    $endpointGroupMap[$ep] = 'ControlPlane'
}
foreach ($ep in $lifecycleEndpoints) {
    if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = 'Lifecycle' }
}
foreach ($grp in $extEndpoints.Keys) {
    foreach ($ep in $extEndpoints[$grp]) {
        $endpointGroupMap[$ep] = $grp
    }
}
if (-not $SkipPKI) {
    foreach ($ep in $pkiEndpoints) {
        if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = 'PKI' }
    }
}

$dynamicEndpoints = @()
if ($Mode -eq 'Public') {
    try {
        $gnsResp = Invoke-HttpSafe -Uri "https://guestnotificationservice.azure.com/urls/allowlist?api-version=2020-01-01&location=$Region" -TimeoutSec 10
        $dynamicEndpoints = @($gnsResp.Content | ConvertFrom-Json) | Where-Object { $_ } | Select-Object -Unique
        foreach ($ep in $dynamicEndpoints) {
            $endpointGroupMap[$ep] = 'GNS'
        }
        Write-Status 'GNS allowlist' ("Loaded $($dynamicEndpoints.Count) endpoints") Green
    }
    catch {
        Write-Status 'GNS allowlist' "Failed: $($_.Exception.Message)" Yellow
        Add-Issue -Severity 'WARN' -Category 'GNS' -Message 'Could not retrieve dynamic GNS allowlist.' -Fix 'Validate guestnotificationservice.azure.com reachability if GNS is needed.'
    }
}

$allTestable = @()
$allTestable += $coreEndpoints
$allTestable += $controlPlaneEndpoints
$allTestable += $lifecycleEndpoints
foreach ($grp in $extEndpoints.Keys) { $allTestable += $extEndpoints[$grp] }
$allTestable += $dynamicEndpoints
if (-not $SkipPKI) { $allTestable += $pkiEndpoints }
$wildcardEndpoints = @($allTestable | Where-Object { $_ -match '^\*\.' } | Select-Object -Unique)
$allTestable = @($allTestable | Where-Object { $_ -and $_ -notmatch '^\*\.' } | Select-Object -Unique)

$httpProbeEndpoints = @(
    'login.microsoftonline.com'
)
if ($script:PreOnboarding -or $script:ProxyMode -eq 'ExplicitProxy' -or $Mode -in @('Private', 'Gateway')) {
    $httpProbeEndpoints += 'management.azure.com'
}
if ($extEndpoints.ContainsKey('SQL')) {
    $httpProbeEndpoints += "dataprocessingservice.$Region.arcdataservices.com"
    $httpProbeEndpoints += "telemetry.$Region.arcdataservices.com"
}
$httpProbeEndpoints += 'oneocsp.microsoft.com'
$httpProbeEndpoints = $httpProbeEndpoints | Select-Object -Unique

$httpBypassedEndpoints = Get-AgentBypassedEndpoints -AgentBypass $agentBypass -Region $Region

Write-Banner ("TESTING $($allTestable.Count) ENDPOINTS")
$index = 0
foreach ($endpoint in $allTestable) {
    $index++
    $group = if ($endpointGroupMap.ContainsKey($endpoint)) { $endpointGroupMap[$endpoint] } else { 'Core' }
    Add-Result -Endpoint $endpoint -Group $group

    $percent = [math]::Round(($index / [Math]::Max($allTestable.Count, 1)) * 100)
    $short = if ($endpoint.Length -gt 58) { $endpoint.Substring(0, 55) + '...' } else { $endpoint }
    Write-Host ("`r  [{0,3}%] {1,-60}" -f $percent, $short) -NoNewline -ForegroundColor Gray

    $resolution = Resolve-Endpoint -Endpoint $endpoint
    if ($resolution.Error) {
        $coreHealthyNoCritical = (($script:AzcmagentCoreHealthy -eq $true) -or (($null -ne $script:AzcmagentCriticalFailures) -and $script:AzcmagentCriticalFailures -eq 0))
        $pkiWarnOnly = ($group -eq 'PKI' -and $coreHealthyNoCritical)
        $dnsSeverity = if ((Test-IsOptionalEndpoint -Endpoint $endpoint -Group $group) -or $pkiWarnOnly) { 'WARN' } else { 'FAIL' }
        $dnsFailureNote = if ($pkiWarnOnly) { 'Name resolution failed; PKI-only warning while Arc core remains healthy.' } else { 'Name resolution failed' }
        Add-Result -Endpoint $endpoint -DNS $dnsSeverity -Notes $dnsFailureNote
        switch ($dnsSeverity) {
            'WARN' { $script:Stats.DNSWarn++ }
            'FAIL' { $script:Stats.DNSFail++ }
        }
        if ($dnsSeverity -eq 'FAIL') {
            Add-Issue -Severity 'HIGH' -Category 'DNS' -Message "Cannot resolve $endpoint." -Fix 'Validate DNS path, split-DNS, and firewall/DNS forwarding.'
        }
        elseif ($pkiWarnOnly) {
            Add-Issue -Severity 'WARN' -Category 'PKI' -Message "PKI endpoint $endpoint could not be resolved." -Fix 'Review PKI/CRL/OCSP reachability only if certificate validation is the target symptom; do not treat this alone as Arc runtime failure when azcmagent reports critical_failures=0.'
        }
        else {
            Add-Issue -Severity 'WARN' -Category 'DNS' -Message "Optional endpoint $endpoint could not be resolved." -Fix 'Review DNS only if this optional endpoint is expected for the installed extension set.'
        }
        continue
    }

    $aRecord = $resolution.Result | Where-Object { $_.Type -eq 'A' -and $_.IPAddress } | Select-Object -First 1
    if (-not $aRecord) {
        $aRecord = $resolution.Result | Where-Object { $_.IPAddress } | Select-Object -First 1
    }
    $ip = if ($aRecord) { $aRecord.IPAddress } else { '-' }
    $type = if (Test-IsPrivateIp -Ip $ip) { 'PRIV' } else { 'PUB' }

    $dnsState = 'OK'
    $dnsNote = ''
    if ($Mode -eq 'Private' -and $type -eq 'PUB' -and ($privateEligible -contains $endpoint)) {
        $dnsState = 'WARN'
        $dnsNote = 'Private mode expected private resolution for this endpoint.'
        $script:Stats.DNSWarn++
        Add-Issue -Severity 'WARN' -Category 'DNS' -Message "$endpoint resolved to public IP $ip while mode is Private." -Fix 'Validate Private Link Scope DNS and conditional forwarding.'
    }
    elseif ($Mode -eq 'Public' -and $type -eq 'PRIV' -and $endpoint -ne 'gbl.his.arc.azure.com') {
        $dnsState = 'WARN'
        $dnsNote = 'Public mode observed private resolution.'
        $script:Stats.DNSWarn++
        Add-Issue -Severity 'WARN' -Category 'DNS' -Message "$endpoint resolved to private IP $ip while mode is Public." -Fix 'Validate split-DNS expectations and ensure this is intentional.'
    }
    else {
        $script:Stats.DNSOK++
    }
    Add-Result -Endpoint $endpoint -IP $ip -Type $type -DNS $dnsState -Notes $dnsNote

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $tcpOk = Test-TcpPort -HostName $endpoint -Port 443 -TimeoutMs 5000
    $sw.Stop()
    $latency = [math]::Round($sw.Elapsed.TotalMilliseconds, 0)

    $tcpState = 'OK'
    $tcpNote = ''
    if ($tcpOk) {
        $script:Stats.TCPOK++
        $tcpState = 'OK'
    }
    else {
        $coreHealthyNoCritical = (($script:AzcmagentCoreHealthy -eq $true) -or (($null -ne $script:AzcmagentCriticalFailures) -and $script:AzcmagentCriticalFailures -eq 0))
        $pkiWarnOnly = ($group -eq 'PKI' -and $coreHealthyNoCritical)
        if ($script:ProxyMode -eq 'ExplicitProxy' -and $type -eq 'PUB' -and $Mode -ne 'Private') {
            $tcpState = 'WARN'
            $tcpNote = 'Direct TCP to endpoint failed, but explicit proxy is configured.'
            $script:Stats.TCPWarn++
        }
        elseif (Test-IsOptionalEndpoint -Endpoint $endpoint -Group $group) {
            $tcpState = 'WARN'
            $tcpNote = 'Optional endpoint did not accept direct TCP 443 during this run; treat as informational unless azcmagent reports core failures.'
            $script:Stats.TCPWarn++
        }
        elseif ($pkiWarnOnly) {
            $tcpState = 'WARN'
            $tcpNote = 'PKI endpoint did not accept direct TCP 443 during this run; treat as informational while Arc core remains healthy.'
            $script:Stats.TCPWarn++
            Add-Issue -Severity 'WARN' -Category 'PKI' -Message "PKI endpoint ${endpoint}:443 was not reachable." -Fix 'Review PKI/CRL/OCSP reachability only if certificate validation is the target symptom; do not treat this alone as Arc runtime failure when azcmagent reports critical_failures=0.'
        }
        else {
            $tcpState = 'FAIL'
            $tcpNote = 'TCP 443 failed.'
            $script:Stats.TCPFail++
            Add-Issue -Severity 'HIGH' -Category 'TCP' -Message "Cannot connect to ${endpoint}:443." -Fix 'Validate routing, firewall, or proxy path expectations for this endpoint.'
        }
    }
    Add-Result -Endpoint $endpoint -TCP $tcpState -Latency $(if ($tcpOk) { "${latency}ms" } else { 'timeout' }) -Notes $tcpNote
}
Write-Host ''

Write-Section 'HTTP Probes'
foreach ($endpoint in $httpProbeEndpoints) {
    $httpBypassApplies = $false
    $endpointHost = $endpoint.Trim().ToLower()
    foreach ($entry in $httpBypassedEndpoints) {
        if (-not $entry) { continue }
        $norm = $entry.Trim().ToLower()
        if (-not $norm) { continue }
        if ($norm.StartsWith('*.')) { $norm = $norm.Substring(1) }
        if ($endpointHost -eq $norm.TrimStart('.') -or ($norm.StartsWith('.') -and $endpointHost.EndsWith($norm))) {
            $httpBypassApplies = $true
            break
        }
    }
    if ($httpBypassApplies) {
        Add-Result -Endpoint $endpoint -HTTP 'SKIP' -Notes 'Skipped because agent bypass category applies.'
        continue
    }

    $forceDirect = $false
    if ($endpoint -eq 'oneocsp.microsoft.com' -and $script:WinHttpProxy) {
        $forceDirect = Test-IsPkiCoveredByBypassOnly -Endpoint 'oneocsp.microsoft.com'
    }

    $group = if ($endpointGroupMap.ContainsKey($endpoint)) { $endpointGroupMap[$endpoint] } else { 'Core' }
    $coreHealthyNoCritical = (($script:AzcmagentCoreHealthy -eq $true) -or (($null -ne $script:AzcmagentCriticalFailures) -and $script:AzcmagentCriticalFailures -eq 0))
    $privatePathHealthyObserved = (
        $script:AzcmagentPrivatePathHealthy -or
        @(
            $script:AzcmagentEndpointMeta.Values | Where-Object {
                $_.Reachable -eq $true -and ($privateEligible -contains $_.HostName) -and (
                    $_.Private -eq 'true' -or
                    ($_.ProxyStatus -eq 'bypassed' -and $_.HostName -match 'his\.arc\.azure\.com|guestconfiguration\.azure\.com')
                )
            }
        ).Count -gt 0 -or
        @(
            $script:Results | Where-Object {
                ($privateEligible -contains $_.Endpoint) -and $_.DNS -eq 'OK' -and $_.TCP -eq 'OK'
            }
        ).Count -gt 0
    )
    $optionalEndpoint = Test-IsOptionalEndpoint -Endpoint $endpoint -Group $group

    $http = Get-HttpStatus -Endpoint $endpoint -ForceDirect:$forceDirect
    if ($http.Success) {
        $script:Stats.HTTPOK++
        Add-Result -Endpoint $endpoint -HTTP ("OK($($http.StatusCode))")
    }
    else {
        $httpDiagnosis = Get-HttpFailureDiagnosis -Endpoint $endpoint -Group $group -ErrorText $http.Error -StatusCode $http.StatusCode -UsingExplicitProxy:($script:ProxyMode -eq 'ExplicitProxy') -ForceDirect:$forceDirect -CoreHealthyNoCritical:$coreHealthyNoCritical
        $privateControlPlaneProxyWarn = ($Mode -eq 'Private' -and $endpoint -eq 'management.azure.com' -and $privatePathHealthyObserved -and $coreHealthyNoCritical)
        if ($privateControlPlaneProxyWarn) {
            $httpDiagnosis = [pscustomobject]@{
                Cause = 'split-network control-plane proxy path degraded'
                Notes = 'Private mode with Arc private path healthy; Azure Resource Manager traffic failed on the current control-plane/proxy path. Azure Arc Private Link Scope does not carry ARM traffic by default, so this matches a split-network pattern unless onboarding or ARM operations are the target symptom.'
                Fix = 'Validate proxy reachability to Azure Resource Manager and confirm split-network intent. If ARM must stay private, configure Resource Management Private Link separately. Treat this as non-blocking for Arc runtime when azcmagent reports critical_failures=0 and private Arc endpoints are reachable.'
                Category = 'ControlPlane'
                ProxyConfiguredButDown = $httpDiagnosis.ProxyConfiguredButDown
            }
        }
        if ($privateControlPlaneProxyWarn -and $coreHealthyNoCritical) {
            $script:Stats.HTTPWarn++
            $httpWarnCategory = 'ControlPlane'
            $httpWarnGroup = 'ControlPlane'
            $httpWarnNotes = $httpDiagnosis.Notes
            $httpWarnMessage = 'management.azure.com failed via proxy/control-plane path while Arc private-capable endpoints remained healthy.'
            $httpWarnFix = $httpDiagnosis.Fix
            Add-Result -Endpoint $endpoint -Group $httpWarnGroup -HTTP $(if ($http.StatusCode) { "WARN($($http.StatusCode))" } else { 'WARN' }) -Notes $httpWarnNotes
            Add-Issue -Severity 'WARN' -Category $httpWarnCategory -Message $httpWarnMessage -Fix $httpWarnFix
        }
        elseif ($optionalEndpoint) {
            $script:Stats.HTTPWarn++
            $optionalHttpNotes = 'Optional endpoint failed HTTP probe; treat as informational unless core also fails.'
            $optionalHttpMessage = "Optional HTTP probe to $endpoint failed; likely $($httpDiagnosis.Cause)."
            $optionalHttpFix = 'Review this endpoint only if the related optional extension or feature is in use.'
            if (Test-IsArcDataTlsPathError -Endpoint $endpoint -ErrorText $http.Error) {
                $optionalHttpNotes = 'Arc Data endpoint returned a malformed TLS message; likely proxy/TLS inspection or path-specific handshake issue, not a general TLS 1.2 limitation.'
                $optionalHttpMessage = "Arc Data HTTP probe to $endpoint failed with a malformed TLS message signature."
                $optionalHttpFix = 'Review TLS inspection, reverse proxy, firewall, or middlebox behavior on the Arc Data path. If core azcmagent endpoints remain healthy, do not treat this alone as host TLS incompatibility.'
            }
            elseif ($httpDiagnosis.Notes) {
                $optionalHttpNotes = $httpDiagnosis.Notes
                $optionalHttpFix = $httpDiagnosis.Fix
            }
            Add-Result -Endpoint $endpoint -HTTP $(if ($http.StatusCode) { "WARN($($http.StatusCode))" } else { 'WARN' }) -Notes $optionalHttpNotes
            Add-Issue -Severity 'WARN' -Category 'HTTP' -Message $optionalHttpMessage -Fix $optionalHttpFix
        }
        elseif ($script:ProxyMode -eq 'ExplicitProxy' -and $forceDirect -eq $false -and $coreHealthyNoCritical) {
            $script:Stats.HTTPWarn++
            $pkiProxyWarnOnly = ($Mode -eq 'Private' -and $group -eq 'PKI' -and $endpoint -eq 'oneocsp.microsoft.com' -and $privatePathHealthyObserved)
            $httpWarnNotes = if ($pkiProxyWarnOnly) {
                'PKI/OCSP endpoint failed over the current proxy-routed path while Arc private-capable endpoints remained healthy. Treat as a PKI revocation-path warning, not Arc runtime failure.'
            }
            else {
                $httpDiagnosis.Notes
            }
            $httpWarnCategory = if ($pkiProxyWarnOnly) { 'PKI' } else { $httpDiagnosis.Category }
            $httpWarnGroup = if ($privateControlPlaneProxyWarn) { 'ControlPlane' } elseif ($pkiProxyWarnOnly) { 'PKI' } else { $group }
            $httpWarnMessage = if ($privateControlPlaneProxyWarn) {
                'management.azure.com failed via proxy/control-plane path while Arc private-capable endpoints remained healthy.'
            }
            elseif ($pkiProxyWarnOnly) {
                'oneocsp.microsoft.com failed over the proxy-routed path; treat this as a PKI/OCSP warning unless certificate revocation checks are the target symptom.'
            }
            else {
                "HTTP probe to $endpoint failed via proxy path; likely $($httpDiagnosis.Cause)."
            }
            $httpWarnFix = if ($pkiProxyWarnOnly) {
                'Validate OCSP/CRL reachability and any proxy exception or inspection policy that affects revocation traffic. Do not treat this alone as Arc core failure while azcmagent reports no critical connectivity failures.'
            }
            else {
                $httpDiagnosis.Fix
            }
            if ($httpWarnCategory -ne 'Proxy' -and $httpWarnCategory -ne 'ControlPlane' -and $httpWarnFix -and $httpWarnFix -notmatch 'critical_failures=0' -and $httpWarnFix -notmatch 'no critical connectivity failures') {
                $httpWarnFix = ($httpWarnFix.TrimEnd('.') + '. Do not treat this alone as Arc core failure while azcmagent reports no critical connectivity failures.')
            }
            Add-Result -Endpoint $endpoint -Group $httpWarnGroup -HTTP $(if ($http.StatusCode) { "WARN($($http.StatusCode))" } else { 'WARN' }) -Notes $httpWarnNotes
            Add-Issue -Severity 'WARN' -Category $httpWarnCategory -Message $httpWarnMessage -Fix $httpWarnFix
        }
        elseif ($script:ProxyMode -eq 'ExplicitProxy' -and $forceDirect -eq $false) {
            $script:Stats.HTTPWarn++
            $httpWarnGroup = if ($privateControlPlaneProxyWarn) { 'ControlPlane' } else { $group }
            $httpWarnMessage = if ($privateControlPlaneProxyWarn) {
                'management.azure.com failed via proxy/control-plane path while Arc private-capable endpoints remained healthy.'
            }
            else {
                "HTTP probe to $endpoint failed via proxy path; likely $($httpDiagnosis.Cause)."
            }
            Add-Result -Endpoint $endpoint -Group $httpWarnGroup -HTTP $(if ($http.StatusCode) { "WARN($($http.StatusCode))" } else { 'WARN' }) -Notes $httpDiagnosis.Notes
            Add-Issue -Severity 'WARN' -Category $httpDiagnosis.Category -Message $httpWarnMessage -Fix $httpDiagnosis.Fix
        }
        else {
            $script:Stats.HTTPFail++
            Add-Result -Endpoint $endpoint -HTTP $(if ($http.StatusCode) { "FAIL($($http.StatusCode))" } else { 'FAIL' }) -Notes $httpDiagnosis.Notes
            Add-Issue -Severity 'MEDIUM' -Category $httpDiagnosis.Category -Message "HTTP probe to $endpoint failed; likely $($httpDiagnosis.Cause)." -Fix $httpDiagnosis.Fix
        }
    }
}

Run-PlatformChecks -DetectedPlatform $Platform

$coreHealthyNoCritical = (($script:AzcmagentCoreHealthy -eq $true) -or (($null -ne $script:AzcmagentCriticalFailures) -and $script:AzcmagentCriticalFailures -eq 0))
if ($coreHealthyNoCritical) {
    Convert-IssuesToNonBlockingWarnings
}

Save-Log

Write-Banner 'DISCLAIMER'
foreach ($line in $script:DisclaimerLines) {
    Write-Host ("  {0}" -f $line) -ForegroundColor DarkGray
}

Write-Banner 'RESULTS'
$results = $script:Results | Sort-Object @{ Expression = {
    switch ($_.Group) {
        'Core' { 0 }
        'PKI' { 1 }
        'SQL' { 2 }
        'AMA' { 3 }
        'MDE' { 4 }
        'WAC' { 5 }
        'KV' { 6 }
        'HRW' { 7 }
        'UM' { 8 }
        'GA' { 9 }
        'GNS' { 10 }
        default { 11 }
    }
} }, Endpoint

$fmt = "  {0,-5} | {1,-50} | {2,-16} | {3,-4} | {4,-8} | {5,-8} | {6,-10} | {7,-7}"
Write-Host ($fmt -f 'Group', 'Endpoint', 'IP', 'Type', 'DNS', 'TCP', 'HTTP', 'Latency') -ForegroundColor Cyan
Write-Host ("  {0,-5}-+-{1,-50}-+-{2,-16}-+-{3,-4}-+-{4,-8}-+-{5,-8}-+-{6,-10}-+-{7,-7}" -f ('-' * 5), ('-' * 50), ('-' * 16), ('-' * 4), ('-' * 8), ('-' * 8), ('-' * 10), ('-' * 7)) -ForegroundColor DarkGray
foreach ($r in $results) {
    $isFail = $r.DNS -eq 'FAIL' -or $r.TCP -eq 'FAIL' -or $r.HTTP -like 'FAIL*'
    $isWarn = $r.DNS -eq 'WARN' -or $r.TCP -eq 'WARN' -or $r.HTTP -like 'WARN*'
    $color = if ($isFail) { 'Red' } elseif ($isWarn) { 'Yellow' } else { 'Green' }
    Write-Host ($fmt -f $r.Group, $r.Endpoint, $r.IP, $r.Type, $r.DNS, $r.TCP, $r.HTTP, $r.Latency) -ForegroundColor $color
    if (-not [string]::IsNullOrWhiteSpace($r.Notes)) {
        Write-Host ("        Notes: {0}" -f $r.Notes) -ForegroundColor DarkGray
    }
}

if ($wildcardEndpoints.Count -gt 0) {
    Write-Host ''
    Write-Host '  Wildcard endpoints (informational only):' -ForegroundColor DarkGray
    foreach ($w in $wildcardEndpoints) {
        $g = if ($endpointGroupMap.ContainsKey($w)) { $endpointGroupMap[$w] } else { '-' }
        Write-Host ("    [{0}] {1}" -f $g, $w) -ForegroundColor DarkGray
    }
}

if ($script:Issues.Count -gt 0) {
    Write-Banner ("ISSUES ($($script:Issues.Count))")
    $ifmt = "  {0,-3} | {1,-8} | {2,-14} | {3}"
    Write-Host ($ifmt -f '#', 'Severity', 'Category', 'Message') -ForegroundColor Cyan
    Write-Host ("  {0,-3}-+-{1,-8}-+-{2,-14}-+-{3}" -f ('-' * 3), ('-' * 8), ('-' * 14), ('-' * 50)) -ForegroundColor DarkGray
    $i = 0
    foreach ($issue in $script:Issues) {
        $i++
        $color = switch ($issue.Severity) {
            'CRITICAL' { 'Red' }
            'HIGH' { 'Red' }
            'MEDIUM' { 'Yellow' }
            'WARN' { 'Yellow' }
            default { 'Gray' }
        }
        Write-Host ($ifmt -f $i, $issue.Severity, $issue.Category, $issue.Message) -ForegroundColor $color
        if ($issue.Fix) {
            Write-Host ("  {0,-3} | {1,-8} | {2,-14} | Fix: {3}" -f '', '', '', $issue.Fix) -ForegroundColor DarkCyan
        }
    }
}

Write-Host ''
Write-Host ('=' * 82) -ForegroundColor DarkCyan
$criticalIssues = @($script:Issues | Where-Object { $_.Severity -in @('CRITICAL', 'HIGH') })
$warningIssues = @($script:Issues | Where-Object { $_.Severity -in @('MEDIUM', 'WARN') })
$coreHealthyNoCritical = (($script:AzcmagentCoreHealthy -eq $true) -or (($null -ne $script:AzcmagentCriticalFailures) -and $script:AzcmagentCriticalFailures -eq 0))
$coreBlockingFails = @(
    $results | Where-Object {
        $_.Group -eq 'Core' -and (
            $_.DNS -eq 'FAIL' -or
            $_.TCP -eq 'FAIL' -or
            ($_.HTTP -like 'FAIL*' -and -not ($script:ProxyMode -eq 'ExplicitProxy' -and $_.Endpoint -eq 'management.azure.com'))
        )
    }
)
$blockingCriticalIssues = @(
    $criticalIssues | Where-Object {
        -not ($coreHealthyNoCritical -and $_.Category -in @('Proxy', 'AgentCheck'))
    }
)
$nonGnsResultWarnings = @(
    $results | Where-Object {
        $_.Group -ne 'GNS' -and (
            $_.DNS -eq 'WARN' -or
            $_.TCP -eq 'WARN' -or
            $_.HTTP -like 'WARN*'
        )
    }
)
$hasFail = ($blockingCriticalIssues.Count -gt 0) -or ($coreBlockingFails.Count -gt 0)
$hasWarn = ($warningIssues.Count -gt 0) -or ($nonGnsResultWarnings.Count -gt 0) -or (($criticalIssues.Count -gt 0) -and ($blockingCriticalIssues.Count -lt $criticalIssues.Count))
if ($coreHealthyNoCritical -and $coreBlockingFails.Count -eq 0) {
    $hasFail = $false
    $hasWarn = (($warningIssues.Count -gt 0) -or ($nonGnsResultWarnings.Count -gt 0) -or (($criticalIssues.Count -gt 0) -and ($blockingCriticalIssues.Count -lt $criticalIssues.Count)))
}
$status = if ($hasFail) { 'FAIL' } elseif ($hasWarn) { 'WARN' } else { 'PASS' }
$statusColor = if ($hasFail) { 'Red' } elseif ($hasWarn) { 'Yellow' } else { 'Green' }
$script:ScenarioSummary = @()
$legacyTls13Endpoints = @(
    $script:AzcmagentEndpointMeta.Values | Where-Object {
        $_.Tls -and $_.Tls -match 'TLS\s*1\.3'
    } | Select-Object -ExpandProperty HostName -Unique
)
$controlPlaneDegraded = @(
    $results | Where-Object {
        $_.Group -eq 'ControlPlane' -and (
            $_.DNS -in @('WARN', 'FAIL') -or
            $_.TCP -in @('WARN', 'FAIL') -or
            $_.HTTP -like 'WARN*' -or
            $_.HTTP -like 'FAIL*'
        )
    }
).Count -gt 0
$optionalDegraded = @(
    $results | Where-Object {
        (Test-IsOptionalEndpoint -Endpoint $_.Endpoint -Group $_.Group) -and (
            $_.DNS -in @('WARN', 'FAIL') -or
            $_.TCP -in @('WARN', 'FAIL') -or
            $_.HTTP -like 'WARN*' -or
            $_.HTTP -like 'FAIL*'
        )
    }
).Count -gt 0
$pkiDegraded = @(
    $results | Where-Object {
        $_.Group -eq 'PKI' -and (
            $_.DNS -in @('WARN', 'FAIL') -or
            $_.TCP -in @('WARN', 'FAIL') -or
            $_.HTTP -like 'WARN*' -or
            $_.HTTP -like 'FAIL*'
        )
    }
).Count -gt 0
$runtimeState = if ($coreHealthyNoCritical -and $coreBlockingFails.Count -eq 0) { 'Healthy' } elseif ($coreBlockingFails.Count -gt 0 -or $blockingCriticalIssues.Count -gt 0) { 'Degraded' } else { 'Unknown' }
$controlPlaneState = if ($controlPlaneDegraded) { 'Degraded' } elseif ($script:PreOnboarding) { 'RequiredForOnboarding' } else { 'HealthyOrNotTargeted' }
$optionalState = if ($optionalDegraded) { 'WarningsPresent' } else { 'HealthyOrNotInUse' }
$pkiState = if ($pkiDegraded) { 'WarningsPresent' } else { 'HealthyOrNotObserved' }
$modeInterpretation = switch ($Mode) {
    'Private' {
        if ($script:AzcmagentPrivatePathHealthy -and $coreHealthyNoCritical) {
            'Private path validated; Arc runtime is using or observing private-capable endpoints successfully.'
        }
        else {
            'Private mode selected; validate private DNS and Private Link Scope behavior for Arc-capable endpoints.'
        }
    }
    'Gateway' {
        if ($script:GatewayUrl) {
            "Gateway mode in effect via $($script:GatewayUrl)."
        }
        else {
            'Gateway mode in effect; validate the local listener and upstream proxy path together.'
        }
    }
    default {
        'Public/direct pattern in effect unless a proxy or private DNS override changes the observed path.'
    }
}
if ($coreHealthyNoCritical) {
    $script:ScenarioSummary += 'Arc core healthy (azcmagent reported no critical connectivity failures).'
}
elseif (($null -ne $script:AzcmagentCriticalFailures) -and $script:AzcmagentCriticalFailures -gt 0) {
    if ($script:AzcmagentFailedEndpoints.Count -gt 0) {
        $script:ScenarioSummary += ('azcmagent reported required Arc connectivity failures for: ' + (($script:AzcmagentFailedEndpoints | Select-Object -Unique) -join ', ') + '.')
    }
    else {
        $script:ScenarioSummary += 'azcmagent reported required Arc connectivity failures to one or more endpoints.'
    }
}
$privateControlPlaneWarnOnly = ($Mode -eq 'Private' -and $coreHealthyNoCritical -and @($results | Where-Object {
    ($privateEligible -contains $_.Endpoint) -and $_.DNS -eq 'OK' -and $_.TCP -eq 'OK'
}).Count -gt 0 -and @($results | Where-Object { $_.Endpoint -eq 'management.azure.com' -and ($_.HTTP -like 'WARN*' -or $_.HTTP -like 'FAIL*') }).Count -gt 0)
$proxyWarnResults = @($results | Where-Object { $_.HTTP -like 'WARN*' -or ($_.Endpoint -eq 'management.azure.com' -and $_.HTTP -like 'FAIL*') })
$proxyWarnEndpoints = @($proxyWarnResults | ForEach-Object { $_.Endpoint } | Where-Object { $_ } | Select-Object -Unique)
$proxyWarnOnlyArcData = ($proxyWarnEndpoints.Count -gt 0 -and @($proxyWarnEndpoints | Where-Object { Test-IsArcDataEndpoint -Endpoint $_ }).Count -eq $proxyWarnEndpoints.Count)
if ($privateControlPlaneWarnOnly) {
    $modeInterpretation = 'Private split-network pattern observed; Arc private endpoints are healthy, while Azure Resource Manager is failing on the separate proxy/control-plane path.'
    $script:ScenarioSummary += 'Private/split-network pattern observed: Arc private-capable endpoints remained healthy while the ARM control-plane path was degraded. Azure Arc Private Link Scope does not include ARM traffic by default.'
}
elseif ($script:ProxyMode -eq 'ExplicitProxy' -and $proxyWarnResults.Count -gt 0) {
    if ($coreHealthyNoCritical -and -not $controlPlaneDegraded -and $proxyWarnOnlyArcData) {
        $script:ScenarioSummary += 'Explicit proxy path showed warnings only for optional SQL/Arc data endpoints (DPS inventory/billing upload and telemetry/log/DMV upload); Arc core connectivity remained healthy.'
    }
    else {
        $script:ScenarioSummary += 'Proxy path degraded for one or more endpoints.'
    }

    $proxyFailureSignatures = @(
        $script:Issues | Where-Object {
            $_.Category -in @('Proxy', 'ProxyPath', 'HTTP', 'ControlPlane') -and $_.Message -match 'likely '
        } | ForEach-Object {
            if ($_.Message -match 'likely ([^.]+)') { $Matches[1].Trim() }
        } | Where-Object { $_ } | Select-Object -Unique
    )
    if ($proxyFailureSignatures.Count -gt 0) {
        $script:ScenarioSummary += ('Observed proxy-path failure signature(s): ' + ($proxyFailureSignatures -join ', ') + '.')
    }
}
if ($optionalDegraded) {
    $script:ScenarioSummary += 'Optional extension/GNS endpoints are degraded; treated as WARN unless core also fails.'
}
if ($pkiDegraded -and $coreHealthyNoCritical) {
    $script:ScenarioSummary += 'PKI/CRL/OCSP warnings were observed, but they do not currently prove Arc runtime failure.'
}
if ($legacyTls12OnlyOs -and $legacyTls13Endpoints.Count -gt 0) {
    $script:ScenarioSummary += 'azcmagent observed endpoints advertising TLS 1.3; on legacy Windows this is informational as long as TLS 1.2 succeeds for required paths.'
}
Write-Host ("  STATUS: {0} | DNS OK/WARN/FAIL: {1}/{2}/{3} | TCP OK/WARN/FAIL: {4}/{5}/{6} | HTTP OK/WARN/FAIL: {7}/{8}/{9}" -f $status, $script:Stats.DNSOK, $script:Stats.DNSWarn, $script:Stats.DNSFail, $script:Stats.TCPOK, $script:Stats.TCPWarn, $script:Stats.TCPFail, $script:Stats.HTTPOK, $script:Stats.HTTPWarn, $script:Stats.HTTPFail) -ForegroundColor $statusColor
if ($null -ne $script:AzcmagentCriticalFailures) {
    Write-Host ("  azcmagent summary: checks_failed={0} critical_failures={1} coreHealthy={2}" -f $script:AzcmagentChecksFailed, $script:AzcmagentCriticalFailures, $(if ($script:AzcmagentCoreHealthy) { 'true' } else { 'false' })) -ForegroundColor DarkGray
}
Write-Host ("  Interpretation: ArcRuntime={0} | ControlPlane={1} | Optional={2} | PKI={3}" -f $runtimeState, $controlPlaneState, $optionalState, $pkiState) -ForegroundColor DarkGray
Write-Host ("  Mode interpretation: {0}" -f $modeInterpretation) -ForegroundColor DarkGray
foreach ($summaryLine in $script:ScenarioSummary) {
    Write-Host ("  Summary: {0}" -f $summaryLine) -ForegroundColor DarkGray
}
Write-Host ("  Scenario: Platform={0} Mode={1} Region={2} Proxy={3}" -f $Platform, $Mode, $Region, $(if ($script:EffectiveProxy) { $script:EffectiveProxy } else { 'Direct' })) -ForegroundColor DarkGray
Write-Host ("  Log: {0}" -f $LogFilePath) -ForegroundColor DarkGray
Write-Host ('=' * 82) -ForegroundColor DarkCyan

Add-Content -Path $LogFilePath -Value ''
Add-Content -Path $LogFilePath -Value '=================== DISCLAIMER ==================='
Add-Content -Path $LogFilePath -Value $script:DisclaimerLines
Add-Content -Path $LogFilePath -Value ''
Add-Content -Path $LogFilePath -Value '=================== RESULTS ==================='
Add-Content -Path $LogFilePath -Value ($fmt -f 'Group', 'Endpoint', 'IP', 'Type', 'DNS', 'TCP', 'HTTP', 'Latency')
Add-Content -Path $LogFilePath -Value (("  {0,-5}-+-{1,-50}-+-{2,-16}-+-{3,-4}-+-{4,-8}-+-{5,-8}-+-{6,-10}-+-{7,-7}" -f ('-' * 5), ('-' * 50), ('-' * 16), ('-' * 4), ('-' * 8), ('-' * 8), ('-' * 10), ('-' * 7)))
foreach ($r in $results) {
    Add-Content -Path $LogFilePath -Value ($fmt -f $r.Group, $r.Endpoint, $r.IP, $r.Type, $r.DNS, $r.TCP, $r.HTTP, $r.Latency)
    if (-not [string]::IsNullOrWhiteSpace($r.Notes)) {
        Add-Content -Path $LogFilePath -Value (("        Notes: {0}" -f $r.Notes))
    }
}
Add-Content -Path $LogFilePath -Value ("Status: $status | Platform=$Platform Mode=$Mode Region=$Region Proxy=" + $(if ($script:EffectiveProxy) { $script:EffectiveProxy } else { 'Direct' }))
if ($script:Issues.Count -gt 0) {
    Add-Content -Path $LogFilePath -Value ''
    Add-Content -Path $LogFilePath -Value '=================== ISSUES ==================='
    foreach ($issue in $script:Issues) {
        Add-Content -Path $LogFilePath -Value ("[$($issue.Severity)] $($issue.Category): $($issue.Message)")
        if ($issue.Fix) {
            Add-Content -Path $LogFilePath -Value ("  Fix: $($issue.Fix)")
        }
    }
}

exit ([int]$hasFail)
