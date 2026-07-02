#Requires -Version 5.1

<#
.SYNOPSIS
    Validates Azure Arc connectivity, DNS resolution, and endpoint reachability
    (public or Azure Private Link).

.DESCRIPTION
    - Automatically detects whether the host uses Azure Arc public endpoints or an
      Azure Arc Private Link Scope (PLS):
        1) 'azcmagent show -j' - if it reports a privateLinkScope => Private
        2) otherwise, resolves 'gbl.his.arc.azure.com' and classifies as Private
           when the IP is RFC1918 (covers the "DNS-based" Private Link scenario)
    - Tests DNS, TCP/443, and (for selected endpoints) HTTP.
    - Runs 'azcmagent check' with the correct flag for the detected mode.
    - Detects and displays the proxy configuration following the agent precedence
      (azcmagent proxy.url > HTTPS_PROXY). The Windows system-wide proxy
      (WinHTTP/WinINET) is shown for information only, because the agent ignores it.
    - Supports environments with Azure Firewall Explicit Proxy.

.PARAMETER Region
    Azure region (default: eastus2).

.PARAMETER Mode
    Auto | Public | Private. Default: Auto.

.PARAMETER ProxyUrl
    HTTP/HTTPS proxy URL (e.g., http://10.0.1.4:8443). If omitted, the script
    auto-detects using the same precedence as the Azure Arc agent: 1) azcmagent
    proxy.url (agent config - takes precedence); 2) the HTTPS_PROXY environment
    variable. The Windows system-wide proxy (WinHTTP/WinINET) is only reported,
    never applied automatically - mirroring the agent.
    Ref: https://learn.microsoft.com/azure/azure-arc/servers/manage-agent-proxy-settings

.PARAMETER LogFilePath
    Log file path. Default: C:\temp\Arclogfile.txt.

.PARAMETER IncludeSQL
    Includes Azure Arc-enabled SQL Server endpoints: data processing service and
    telemetry (*.arcdataservices.com), san-af (legacy), and graph.microsoft.com
    (Microsoft Entra authentication). Aligned with the official Arc SQL connectivity
    test (DPS => 200, telemetry => 401).

.PARAMETER IncludeAMA
    Includes Azure Monitor Agent (AMA) endpoints.

.PARAMETER IncludeMDE
    Includes Microsoft Defender for Endpoint endpoints.

.PARAMETER IncludeWAC
    Includes Windows Admin Center endpoints.

.PARAMETER CheckIncludeAll
    Makes 'azcmagent check' validate everything: adds '--extensions all' (endpoints
    for all supported extensions) and '--include-all' (extended use cases, e.g.,
    Windows Server pay-as-you-go). Useful before onboarding. Replaces the
    '--extensions sql' that -IncludeSQL would add.

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1
    Auto-detects the mode (Public/Private) and uses the default region 'eastus2'.

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1 -Region brazilsouth -IncludeSQL -IncludeAMA
    Runs against brazilsouth including SQL and AMA endpoints.

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1 -Region eastus2 -ProxyUrl http://10.0.1.4:8443
    Forces an explicit proxy for all HTTP tests.

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1 -Region westeurope -Mode Public
    Forces Public mode on westeurope (useful to validate the internet endpoint
    list when the host does not have the agent installed yet).

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1 -Region brazilsouth -Mode Private -LogFilePath D:\logs\arc-pls.txt
    Forces Private Link validation and writes the log to a custom path. Adds the
    '--enable-pls-check' flag to 'azcmagent check'.

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1 -Region southcentralus -Verbose -IncludeSQL -IncludeAMA -IncludeMDE -IncludeWAC
    Runs with detailed verbose output and all endpoint groups.
    Common regions: eastus, eastus2, westus2, westus3, centralus, northeurope,
    westeurope, uksouth, francecentral, switzerlandnorth, southeastasia,
    japaneast, australiaeast, brazilsouth, southafricanorth, uaenorth.

.EXAMPLE
    PS> .\ArcEndpointCheck.ps1 -Mode Private -CheckIncludeAll
    Runs 'azcmagent check' with '--extensions all --include-all' (endpoints for all
    extensions + extended use cases) in Private mode.

.NOTES
    Requires PowerShell 5.1+ on Windows (uses netsh, Resolve-DnsName, and azcmagent.exe).
    azcmagent.exe is optional (only for the final check).
    Exit code: 0 = all tests OK; 1 = at least one failure.
    Endpoint lists aligned with the Connected Machine agent network requirements and
    its extensions (AMA/SQL/MDE/WAC).

.LINK
    https://azurearcjumpstart.com
#>

[CmdletBinding()]
param(
    [string]$Region = 'eastus2',

    [ValidateSet('Auto', 'Public', 'Private')]
    [string]$Mode = 'Auto',

    [string]$ProxyUrl,

    [string]$LogFilePath = 'C:\temp\Arclogfile.txt',

    [switch]$IncludeSQL,
    [switch]$IncludeAMA,
    [switch]$IncludeMDE,
    [switch]$IncludeWAC,

    [switch]$CheckIncludeAll
)

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # speeds up Invoke-WebRequest and Test-NetConnection

$logDir = Split-Path -Path $LogFilePath -Parent
if ($logDir -and -not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
Set-Content -Path $LogFilePath -Value "Script started at $(Get-Date -Format o)" -Force

$script:Stats     = [ordered]@{ OK = 0; Fail = 0; Warn = 0 }
$script:LogBuffer = [System.Collections.ArrayList]::new()
$script:Results   = [System.Collections.ArrayList]::new()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Test-IsValidProxyUri {
    <#
    .SYNOPSIS
        Returns $true only when the input is a well-formed absolute http:// or
        https:// URI. Rejects informational strings that azcmagent returns when
        the proxy is not configured (e.g. "proxy.url has not been set").
    #>
    param([string]$Candidate)
    if (-not $Candidate) { return $false }
    $parsed = $null
    return (
        [System.Uri]::TryCreate($Candidate, [System.UriKind]::Absolute, [ref]$parsed) -and
        $parsed.Scheme -in @('http', 'https')
    )
}

function Add-Result {
    param(
        [Parameter(Mandatory)] [string]$Endpoint,
        [string]$Group = 'Core',
        [string]$IP    = '-',
        [string]$Type  = '-',
        [string]$DNS   = '-',
        [string]$TCP   = '-',
        [string]$HTTP  = '-',
        [string]$Latency = '-'
    )
    # Check if endpoint already exists and update
    $existing = $script:Results | Where-Object { $_.Endpoint -eq $Endpoint }
    if ($existing) {
        if ($IP      -ne '-') { $existing.IP      = $IP }
        if ($Type    -ne '-') { $existing.Type    = $Type }
        if ($DNS     -ne '-') { $existing.DNS     = $DNS }
        if ($TCP     -ne '-') { $existing.TCP     = $TCP }
        if ($HTTP    -ne '-') { $existing.HTTP    = $HTTP }
        if ($Latency -ne '-') { $existing.Latency = $Latency }
    }
    else {
        [void]$script:Results.Add([ordered]@{
            Endpoint = $Endpoint
            Group    = $Group
            IP       = $IP
            Type     = $Type
            DNS      = $DNS
            TCP      = $TCP
            HTTP     = $HTTP
            Latency  = $Latency
        })
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('Info', 'OK', 'Fail', 'Warn')] [string]$Level = 'Info',
        [switch]$NoCount
    )
    $color = @{ Info = 'Gray'; OK = 'Green'; Fail = 'Red'; Warn = 'Yellow' }[$Level]
    $line  = "[{0}] [{1,-4}] {2}" -f (Get-Date -Format HH:mm:ss), $Level.ToUpper(), $Message
    Write-Host $line -ForegroundColor $color
    [void]$script:LogBuffer.Add($line)

    if (-not $NoCount) {
        if ($Level -eq 'OK')   { $script:Stats.OK++ }
        if ($Level -eq 'Fail') { $script:Stats.Fail++ }
        if ($Level -eq 'Warn') { $script:Stats.Warn++ }
    }
}

function Save-LogBuffer {
    if ($script:LogBuffer.Count -gt 0) {
        Add-Content -Path $LogFilePath -Value $script:LogBuffer
        $script:LogBuffer.Clear()
    }
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory)] [string]$ComputerName,
        [int]$Port = 443,
        [int]$TimeoutMs = 5000
    )
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $iar = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
            $client.EndConnect($iar) | Out-Null
            return $true
        }
        return $false
    }
    catch { return $false }
    finally { $client.Close() }
}

function Invoke-WebRequestSafe {
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [int]$TimeoutSec = 10
    )
    $params = @{
        Uri             = $Uri
        Method          = 'Get'
        UseBasicParsing = $true
        TimeoutSec      = $TimeoutSec
        ErrorAction     = 'Stop'
    }
    if ($script:EffectiveProxy) {
        $params['Proxy'] = $script:EffectiveProxy
        $params['ProxyUseDefaultCredentials'] = $true
    }
    elseif ($PSVersionTable.PSVersion.Major -ge 6) {
        # PS 6+: mirror the agent, which IGNORES the system-wide proxy. On PS 5.1 the
        # same effect is achieved by neutralizing .NET's DefaultWebProxy during setup.
        $params['NoProxy'] = $true
    }
    return Invoke-WebRequest @params
}

# ---------------------------------------------------------------------------
# Proxy detection and display
# ---------------------------------------------------------------------------
$script:EffectiveProxy = $null

function Get-ProxyDiagnostics {
    Write-Log '=== PROXY DIAGNOSTICS ===' Info -NoCount
    [void]$script:LogBuffer.Add('')

    # Effective proxy precedence (used by this script's HTTP tests) — mirrors the
    # behavior of the Azure Connected Machine agent on Windows:
    #   1) -ProxyUrl            (explicit operator override)
    #   2) azcmagent proxy.url  (agent config — TAKES PRECEDENCE over env vars)
    #   3) HTTPS_PROXY (env)    (system-wide)
    # The agent IGNORES the Windows system-wide proxy (WinHTTP/WinINET); that is why
    # the WinHTTP value below is only REPORTED, never applied automatically.
    # Ref: https://learn.microsoft.com/azure/azure-arc/servers/manage-agent-proxy-settings

    # 1) -ProxyUrl parameter (validated as an absolute http/https URI)
    if ($ProxyUrl) {
        if (Test-IsValidProxyUri -Candidate $ProxyUrl) {
            Write-Log "Proxy from parameter: $ProxyUrl" Info -NoCount
            $script:EffectiveProxy = $ProxyUrl
        }
        else {
            Write-Log "Proxy from parameter INVALID (expected http:// or https://): $ProxyUrl" Warn
        }
    }

    # WinHTTP (informational only — the agent ignores the system-wide proxy)
    # Bilingual regex: EN "Proxy Server(s)" / pt-BR "Servidor(es) Proxy"
    try {
        $winhttp = netsh winhttp show proxy 2>$null
        $winhttpText = ($winhttp | Out-String).Trim()
        if ($winhttpText -match 'Proxy Server\(s\)\s*:\s*(.+)|Servidor\(es\) Proxy\s*:\s*(.+)') {
            $winhttpProxy = ($Matches[1], $Matches[2] | Where-Object { $_ } | Select-Object -First 1).Trim()
            Write-Log "WinHTTP Proxy: $winhttpProxy (informational — the agent ignores the system-wide proxy)" Info -NoCount
        }
        else {
            Write-Log 'WinHTTP Proxy: Direct (no proxy)' Info -NoCount
        }
        if ($winhttpText -match 'Bypass List\s*:\s*(.+)|Lista de bypass\s*:\s*(.+)') {
            $bypassVal = ($Matches[1], $Matches[2] | Where-Object { $_ } | Select-Object -First 1).Trim()
            Write-Log "WinHTTP Bypass: $bypassVal" Info -NoCount
        }
    }
    catch {
        Write-Log "WinHTTP: unable to query ($($_.Exception.Message))" Warn
    }

    # 2) azcmagent config (proxy.url TAKES PRECEDENCE over HTTPS_PROXY)
    #    IMPORTANT: azcmagent returns informational phrases when the value is not
    #    configured (e.g. "proxy.url has not been set"). We validate with
    #    Test-IsValidProxyUri to accept ONLY real http/https URIs.
    $azcm = Get-AzcmagentPath
    if ($azcm) {
        try {
            $rawProxyUrl = & $azcm config get proxy.url 2>$null
            $rawProxyUrlTrimmed = if ($rawProxyUrl) { ($rawProxyUrl | Out-String).Trim() } else { '' }

            if (Test-IsValidProxyUri -Candidate $rawProxyUrlTrimmed) {
                Write-Log "azcmagent proxy.url: $rawProxyUrlTrimmed" Info -NoCount
                if (-not $script:EffectiveProxy) {
                    $script:EffectiveProxy = $rawProxyUrlTrimmed
                }
            }
            else {
                # Informational message (e.g. "proxy.url has not been set")
                if ($rawProxyUrlTrimmed) {
                    Write-Log "azcmagent proxy.url: $rawProxyUrlTrimmed" Info -NoCount
                }
                else {
                    Write-Log 'azcmagent proxy.url: (not configured)' Info -NoCount
                }
            }

            $bypass = & $azcm config get proxy.bypass 2>$null
            $bypassTrimmed = if ($bypass) { ($bypass | Out-String).Trim() } else { '' }
            if ($bypassTrimmed) {
                Write-Log "azcmagent proxy.bypass: $bypassTrimmed" Info -NoCount
            }
        }
        catch {
            Write-Log "azcmagent config: failed to query ($($_.Exception.Message))" Warn
        }
    }

    # 3) Environment variables (checks Machine -> Process -> User)
    $envProxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Machine')
    if (-not $envProxy) { $envProxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process') }
    if (-not $envProxy) { $envProxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'User') }
    $envNoProxy = [Environment]::GetEnvironmentVariable('NO_PROXY', 'Machine')
    if (-not $envNoProxy) { $envNoProxy = [Environment]::GetEnvironmentVariable('NO_PROXY', 'Process') }
    if (-not $envNoProxy) { $envNoProxy = [Environment]::GetEnvironmentVariable('NO_PROXY', 'User') }
    if ($envProxy) {
        Write-Log "Env HTTPS_PROXY: $envProxy" Info -NoCount
        if (-not $script:EffectiveProxy) {
            if (Test-IsValidProxyUri -Candidate $envProxy) {
                $script:EffectiveProxy = $envProxy
            }
            else {
                Write-Log "Env HTTPS_PROXY INVALID (expected http:// or https://): $envProxy" Warn
            }
        }
    }
    else {
        Write-Log 'Env HTTPS_PROXY: (not set)' Info -NoCount
    }
    if ($envNoProxy) {
        Write-Log "Env NO_PROXY: $envNoProxy" Info -NoCount
    }

    if ($script:EffectiveProxy) {
        Write-Log "Effective proxy for HTTP tests: $($script:EffectiveProxy)" Info -NoCount
    }
    else {
        Write-Log 'Effective proxy: Direct (no proxy — HTTP tests go direct, like the agent)' Info -NoCount
    }

    [void]$script:LogBuffer.Add('')
}

# ---------------------------------------------------------------------------
# Automatic Public vs Private detection
# ---------------------------------------------------------------------------
function Get-AzcmagentPath {
    $candidate = Join-Path $env:ProgramFiles 'AzureConnectedMachineAgent\azcmagent.exe'
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Test-IsPrivateIp {
    param([string]$Ip)
    if (-not $Ip) { return $false }
    try {
        $bytes = ([System.Net.IPAddress]::Parse($Ip)).GetAddressBytes()
    }
    catch { return $false }

    # RFC1918 + 100.64/10 (CGNAT, common in corporate networks)
    return ($bytes[0] -eq 10) -or
           ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or
           ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
           ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127)
}

function Resolve-ArcMode {
    Write-Log 'Detecting Arc mode (Public/Private)...' Info -NoCount

    # 1) Via azcmagent show -j
    $azcm = Get-AzcmagentPath
    if ($azcm) {
        try {
            $json = & $azcm show -j 2>$null | ConvertFrom-Json
            $pls = $json.privateLinkScope
            if ($pls) {
                Write-Log "azcmagent reports privateLinkScope: $pls" Info -NoCount
                return 'Private'
            }
            else {
                # Do NOT conclude Public here: fall through to the DNS heuristic below.
                # Private Link can be "DNS-based" (Private DNS Zones) without the agent
                # exposing the PLS locally in 'azcmagent show -j'.
                Write-Log 'azcmagent does not report privateLinkScope; confirming via DNS...' Info -NoCount
            }
        }
        catch {
            Write-Log "Failed to query azcmagent show -j: $($_.Exception.Message). Falling back to DNS." Warn
        }
    }
    else {
        Write-Log 'azcmagent.exe not found. Using DNS fallback.' Warn
    }

    # 2) Fallback: resolve gbl.his.arc.azure.com
    try {
        $dns = Resolve-DnsName -Name 'gbl.his.arc.azure.com' -Type A -ErrorAction Stop
        $ip  = ($dns | Where-Object IPAddress | Select-Object -First 1).IPAddress
        if (Test-IsPrivateIp -Ip $ip) {
            Write-Log "gbl.his.arc.azure.com resolves to a private IP ($ip) -> Private Link" Info -NoCount
            return 'Private'
        }
        else {
            Write-Log "gbl.his.arc.azure.com resolves to a public IP ($ip) -> Public" Info -NoCount
            return 'Public'
        }
    }
    catch {
        Write-Log 'Could not resolve gbl.his.arc.azure.com - assuming Public.' Warn
        return 'Public'
    }
}

# ---------------------------------------------------------------------------
# Mode and proxy detection
# ---------------------------------------------------------------------------
Get-ProxyDiagnostics

# Alignment with the agent: the Azure Connected Machine agent IGNORES the Windows
# system-wide proxy (WinINET/WinHTTP). If no effective proxy was detected, we
# neutralize .NET's DefaultWebProxy (PS 5.1) so that the HTTP tests also go direct.
# On PS 6+ this is done via -NoProxy.
if (-not $script:EffectiveProxy -and $PSVersionTable.PSVersion.Major -lt 6) {
    try { [System.Net.WebRequest]::DefaultWebProxy = $null } catch { }
}

if ($Mode -eq 'Auto') {
    $Mode = Resolve-ArcMode
}
Write-Log "Selected mode: $Mode | Region: $Region" Info -NoCount

# Reset stats: the test phase starts here (detection does not count)
$script:Stats.OK   = 0
$script:Stats.Fail = 0
$script:Stats.Warn = 0

# ---------------------------------------------------------------------------
# Endpoints — organized by functional group
# ---------------------------------------------------------------------------

# Endpoints that CAN resolve to a private IP via Azure Private Link Scope.
# Everything NOT in this list is always public — do not raise a WARN in Private mode.
$canBePrivateEndpoints = @(
    'gbl.his.arc.azure.com'
    'agentserviceapi.guestconfiguration.azure.com'
    'dc.services.visualstudio.com'
    'global.handler.control.monitor.azure.com'
)

# Core Arc (required) — aligned with the Connected Machine agent network-requirements.
# Doc: https://learn.microsoft.com/azure/azure-arc/servers/network-requirements
$coreEndpoints = @(
    # AAD / Identity (always; Public)
    'login.windows.net'
    'login.microsoftonline.com'
    'pas.windows.net'

    # ARM (connect/disconnect; Public unless Resource Management Private Link)
    'management.azure.com'

    # Arc HIMDS (always; Private via PLS)
    'gbl.his.arc.azure.com'

    # Guest Configuration / extension management (always; Private via PLS)
    'agentserviceapi.guestconfiguration.azure.com'

    # Agent install/update (Public)
    'packages.microsoft.com'
    'download.microsoft.com'

    # Telemetry (optional; NOT used on agents 1.24+; Public)
    'dc.services.visualstudio.com'
)

# SQL endpoints (optional via -IncludeSQL) — Arc-enabled SQL Server.
# Doc: network-requirements + sql/.../data-collection. All Public; TLS 1.2/1.3.
$sqlEndpoints = @()
if ($IncludeSQL) {
    $sqlEndpoints = @(
        # Data processing service + telemetry (extensions from Mar/2024 onward)
        "dataprocessingservice.$Region.arcdataservices.com"
        "telemetry.$Region.arcdataservices.com"
        # Legacy: used by extensions until Feb 13, 2024
        "san-af-$Region-prod.azurewebsites.net"
        # Arc SQL Microsoft Entra authentication (Public). Only needed when using
        # Entra auth; NOT a core agent endpoint. Reachable directly, but may be
        # blocked on a split-tunnel proxy -> DNS/TCP only (no HTTP probe).
        'graph.microsoft.com'
    )
}

# AMA endpoints (optional via -IncludeAMA) — Azure Monitor Agent.
# Doc: azure-monitor-agent-network-configuration. The <workspace-id>.ods and
# <dce>.ingest.monitor endpoints require specific IDs -> not generically testable.
$amaEndpoints = @()
if ($IncludeAMA) {
    $amaEndpoints = @(
        'global.handler.control.monitor.azure.com'   # control service
        'global.prod.microsoftmetrics.com'           # metrics service
        "$Region.handler.control.monitor.azure.com"  # regional DCRs
        "$Region.monitoring.azure.com"               # custom metrics (optional)
    )
}

# MDE endpoints (optional via -IncludeMDE)
$mdeEndpoints = @()
if ($IncludeMDE) {
    $mdeEndpoints = @(
        'unitedstates.x.cp.wd.microsoft.com'
        'us-v20.events.data.microsoft.com'
    )
}

# WAC endpoints (optional via -IncludeWAC)
# Note: 'pas.windows.net' is already in $coreEndpoints and $endpointGroupMap
# preserves Core precedence, avoiding duplication in the summary.
$wacEndpoints = @()
if ($IncludeWAC) {
    $wacEndpoints = @(
        "$Region.service.waconazure.com"
    )
}

# Endpoints that respond to HTTP (L7 validation — 200/400/401/403/404 = reachable).
# Does NOT include graph.microsoft.com: it is the Arc SQL Entra auth endpoint (optional)
# and is often blocked on a split-tunnel proxy; the official Arc SQL connectivity
# test itself validates only DPS + telemetry.
$httpProbeEndpoints = @(
    'login.windows.net'
    'login.microsoftonline.com'
    'management.azure.com'
)
if ($IncludeSQL) {
    # Aligned with the official Arc SQL test: DPS expects 200; telemetry expects 401
    # (both treated as reachable here).
    $httpProbeEndpoints += "dataprocessingservice.$Region.arcdataservices.com"
    $httpProbeEndpoints += "telemetry.$Region.arcdataservices.com"
}

# Maps a group per endpoint for the summary. Core has PRECEDENCE: if an endpoint
# appears in more than one group (e.g. pas.windows.net in Core and WAC), we keep 'Core'.
$endpointGroupMap = @{}
foreach ($ep in $coreEndpoints) { $endpointGroupMap[$ep] = 'Core' }
foreach ($ep in $sqlEndpoints)  { if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = 'SQL' } }
foreach ($ep in $amaEndpoints)  { if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = 'AMA' } }
foreach ($ep in $mdeEndpoints)  { if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = 'MDE' } }
foreach ($ep in $wacEndpoints)  { if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = 'WAC' } }

# Dynamic allowlist (Public mode only; under PLS traffic goes via PE)
$dynamicEndpoints = @()
if ($Mode -eq 'Public') {
    try {
        Write-Log 'Fetching dynamic endpoints from guestnotificationservice...' Info -NoCount
        $uri  = "https://guestnotificationservice.azure.com/urls/allowlist?api-version=2020-01-01&location=$Region"
        $resp = Invoke-WebRequestSafe -Uri $uri
        $dynamicEndpoints = @($resp.Content | ConvertFrom-Json) | Where-Object { $_ }
        if ($dynamicEndpoints.Count -gt 0) {
            $totalGNS = $dynamicEndpoints.Count

            # Filter: keep only the region's primary endpoints.
            # Primary namespaces contain '<N>p-' (e.g. 1p-, 2p-), secondary contain '<N>s-'.
            # Extract cluster IDs from the primaries and filter children by them.
            $primaryClusterIds = [System.Collections.ArrayList]::new()
            foreach ($dep in $dynamicEndpoints) {
                if ($dep -match '^azgn-.+\dp-.+?-(\w+)\.servicebus') {
                    [void]$primaryClusterIds.Add($Matches[1])
                }
            }

            if ($primaryClusterIds.Count -gt 0) {
                $filteredGNS = [System.Collections.ArrayList]::new()
                foreach ($dep in $dynamicEndpoints) {
                    if ($dep -match '^azgn-') {
                        [void]$filteredGNS.Add($dep)   # always keep namespace-level
                    }
                    else {
                        foreach ($cid in $primaryClusterIds) {
                            if ($dep -like "*$cid*") {
                                [void]$filteredGNS.Add($dep)
                                break
                            }
                        }
                    }
                }
                $skipped = $totalGNS - $filteredGNS.Count
                $dynamicEndpoints = @($filteredGNS)
                if ($skipped -gt 0) {
                    Write-Log "Dynamic endpoints obtained: $totalGNS total, $($filteredGNS.Count) primary ($skipped secondary filtered out)" OK
                }
                else {
                    Write-Log "Dynamic endpoints obtained: $totalGNS endpoint(s)" OK
                }
            }
            else {
                Write-Log "Dynamic endpoints obtained: $totalGNS endpoint(s)" OK
            }

            foreach ($dep in $dynamicEndpoints) {
                $endpointGroupMap[$dep] = 'GNS'
            }
        }
    }
    catch {
        # The dynamic allowlist is AUXILIARY: its unavailability must not break the
        # exit code (WARN, not FAIL). Common when forcing -Mode Public on a host that,
        # in practice, routes GNS via Private Link / firewall.
        Write-Log "Failed to obtain dynamic endpoints (auxiliary allowlist): $($_.Exception.Message)" Warn
    }
}
else {
    Write-Log 'Private mode: skipping public allowlist query.' Info -NoCount
}

$allEndpoints = @(
    $coreEndpoints + $sqlEndpoints + $amaEndpoints + $mdeEndpoints +
    $wacEndpoints + $dynamicEndpoints |
    Where-Object { $_ } |
    Select-Object -Unique
)

Write-Log "Total endpoints to test: $($allEndpoints.Count)" Info -NoCount
[void]$script:LogBuffer.Add('')

# ---------------------------------------------------------------------------
# Tests: DNS + TCP/443 (consistency check against the detected mode)
# ---------------------------------------------------------------------------
foreach ($ep in $allEndpoints) {
    $ep = $ep.Trim()
    if (-not $ep) { continue }

    Write-Verbose "Testing: $ep"

    [void]$script:LogBuffer.Add('-' * 60)
    $group = if ($endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] } else { 'Dyn' }
    Add-Result -Endpoint $ep -Group $group

    # DNS (with 1 retry on a transient failure, e.g. SERVFAIL when resolving many names)
    $dns = $null
    $dnsErr = $null
    foreach ($attempt in 1..2) {
        try { $dns = Resolve-DnsName -Name $ep -ErrorAction Stop; $dnsErr = $null; break }
        catch { $dnsErr = $_; if ($attempt -lt 2) { Start-Sleep -Milliseconds 300 } }
    }
    if ($dnsErr) {
        # Dynamic endpoints (GNS) are AUXILIARY: a DNS failure on them becomes WARN
        # (not FAIL), because a transient SERVFAIL when resolving dozens of
        # 'servicebus' names must not break the exit code. Other groups stay FAIL.
        $existingD = $script:Results | Where-Object { $_.Endpoint -eq $ep }
        if ($group -eq 'GNS') {
            Write-Log "DNS WARN $ep - $($dnsErr.Exception.Message) (dynamic/auxiliary endpoint)" Warn
            if ($existingD) { $existingD.DNS = 'WARN' }
        }
        else {
            Write-Log "DNS FAIL $ep - $($dnsErr.Exception.Message)" Fail
            if ($existingD) { $existingD.DNS = 'FAIL' }
        }
        continue
    }

    # Prefer IPv4 (A record): Azure Private Link and most Arc endpoints are resolved
    # by A record. A public AAAA (IPv6) may coexist with the private A; if chosen, it
    # causes an incorrect PUBLIC classification and tests over a possibly
    # nonexistent/unrouted IPv6 path.
    $rec = $dns | Where-Object { $_.Type -eq 'A' -and $_.IPAddress } | Select-Object -First 1
    if (-not $rec) { $rec = $dns | Where-Object IPAddress | Select-Object -First 1 }
    $ip   = $rec.IPAddress
    $kind = if (Test-IsPrivateIp -Ip $ip) { 'PRIVATE' } else { 'PUBLIC' }

    # Update result
    $existing = $script:Results | Where-Object { $_.Endpoint -eq $ep }
    if ($existing) { $existing.IP = $ip; $existing.Type = $kind }

    # DNS vs mode mismatch alert
    # Only endpoints in $canBePrivateEndpoints should resolve to a private IP.
    # All others (AAD, ARM, CDN, SQL, AMA, MDE, WAC, GNS) are always public.
    $canBePrivate = $canBePrivateEndpoints -contains $ep
    $mismatch = $false
    if ($Mode -eq 'Private' -and $kind -eq 'PUBLIC' -and $canBePrivate) {
        $mismatch = $true
    }
    elseif ($Mode -eq 'Public' -and $kind -eq 'PRIVATE') {
        $mismatch = $true
    }
    if ($mismatch) {
        Write-Log "DNS WARN $ep -> $ip [$kind] (expected the opposite for $Mode mode)" Warn
        $existing2 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
        if ($existing2) { $existing2.DNS = 'WARN' }
    }
    else {
        Write-Log "DNS OK   $ep -> $ip [$kind]" OK
        $existing2 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
        if ($existing2) { $existing2.DNS = 'OK' }
    }

    # TCP/443 (TcpClient with timeout — much faster than Test-NetConnection)
    $tcpSw = [System.Diagnostics.Stopwatch]::StartNew()
    $tcpOk = Test-TcpPort -ComputerName $ep -Port 443 -TimeoutMs 5000
    $tcpSw.Stop()
    $latencyMs = [math]::Round($tcpSw.Elapsed.TotalMilliseconds, 0)

    $existing3 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
    if ($tcpOk) {
        Write-Log "TCP OK   ${ep}:443 (${latencyMs}ms)" OK
        if ($existing3) { $existing3.TCP = 'OK'; $existing3.Latency = "${latencyMs}ms" }
    }
    else {
        Write-Log "TCP FAIL ${ep}:443 (timeout/refused)" Fail
        if ($existing3) { $existing3.TCP = 'FAIL'; $existing3.Latency = 'timeout' }
    }
}

# ---------------------------------------------------------------------------
# HTTP tests (401/403/400 are treated as success: endpoint requires auth)
# Detects azcmagent proxy.bypass to skip HTTP tests on bypassed endpoints
# ---------------------------------------------------------------------------
$proxyBypassCategories = @()
$azcmPath = Get-AzcmagentPath
if ($azcmPath -and $script:EffectiveProxy) {
    try {
        $bypassRaw = & $azcmPath config get proxy.bypass 2>$null
        $bypassRawStr = if ($bypassRaw) { ($bypassRaw | Out-String).Trim() } else { '' }
        if ($bypassRawStr) {
            $bypassClean = $bypassRawStr.Trim('[', ']')
            $proxyBypassCategories = $bypassClean -split ',' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ }
        }
    }
    catch { }
}

# Map of bypass categories -> affected endpoints (per the official doc:
# https://learn.microsoft.com/azure/azure-arc/servers/manage-agent-proxy-settings).
# IMPORTANT: 'graph.microsoft.com' is NOT covered by any bypass — the agent
# uses the proxy for it; therefore it must NOT be skipped in the HTTP tests.
# 'ArcData' is valid from agent 1.36 onward; in earlier versions the
# arcdataservices endpoints fell under the 'Arc' category.
$bypassCategoryEndpoints = @{
    'AAD'     = @('login.windows.net', 'login.microsoftonline.com', 'pas.windows.net')
    'ARM'     = @('management.azure.com')
    'AMA'     = @(
        'global.handler.control.monitor.azure.com'
        "$Region.handler.control.monitor.azure.com"
        'management.azure.com'
        "$Region.monitoring.azure.com"
    )
    'Arc'     = @('gbl.his.arc.azure.com', 'agentserviceapi.guestconfiguration.azure.com')
    'ArcData' = @(
        "dataprocessingservice.$Region.arcdataservices.com"
        "telemetry.$Region.arcdataservices.com"
    )
}

$httpBypassedEndpoints = [System.Collections.ArrayList]::new()
foreach ($cat in $proxyBypassCategories) {
    if ($bypassCategoryEndpoints.ContainsKey($cat)) {
        foreach ($bep in $bypassCategoryEndpoints[$cat]) {
            if ($httpBypassedEndpoints -notcontains $bep) {
                [void]$httpBypassedEndpoints.Add($bep)
            }
        }
    }
}

foreach ($ep in $httpProbeEndpoints) {
    $ep = $ep.Trim()
    if (-not $ep) { continue }

    # If the endpoint is in the azcmagent bypass and we use a proxy, an HTTP test via proxy would give a false positive
    if ($httpBypassedEndpoints -contains $ep) {
        Add-Result -Endpoint $ep -HTTP 'SKIP (bypass)'
        Write-Log "HTTP SKIP $ep (azcmagent proxy.bypass covers this endpoint — agent does not use a proxy)" Info -NoCount
        continue
    }

    [void]$script:LogBuffer.Add('-' * 60)
    Add-Result -Endpoint $ep

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-WebRequestSafe -Uri "https://$ep" -TimeoutSec 10
        $sw.Stop()
        $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        Write-Log "HTTP OK  $ep -> $($resp.StatusCode) in ${elapsed}s" OK
        $existing4 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
        if ($existing4) { $existing4.HTTP = "OK ($($resp.StatusCode))" }
    }
    catch {
        if ($sw.IsRunning) { $sw.Stop() }
        $code = $null
        if ($_.Exception.Response) {
            try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        }
        if ($code -in 400, 401, 403, 404) {
            Write-Log "HTTP OK  $ep -> $code (expected without auth/without root handler)" OK
            $existing4 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
            if ($existing4) { $existing4.HTTP = "OK ($code)" }
        }
        elseif ($code) {
            Write-Log "HTTP FAIL $ep -> $code" Fail
            $existing4 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
            if ($existing4) { $existing4.HTTP = "FAIL ($code)" }
        }
        else {
            Write-Log "HTTP FAIL $ep - $($_.Exception.Message)" Fail
            $existing4 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
            if ($existing4) { $existing4.HTTP = 'FAIL' }
        }
    }
}

# ---------------------------------------------------------------------------
# azcmagent check
# ---------------------------------------------------------------------------
[void]$script:LogBuffer.Add('=' * 60)
$azcm = Get-AzcmagentPath
if ($azcm) {
    $checkArgs = @('check', '--location', $Region, '--cloud', 'AzureCloud')
    if ($CheckIncludeAll) {
        # Official doc: '--extensions' and '--include-all' are ORTHOGONAL.
        #   --extensions all -> endpoints for ALL extensions (SQL, etc.)
        #   --include-all    -> EXTENDED use cases (e.g. Windows Server PAYG)
        # We combine both for full coverage.
        $checkArgs += @('--extensions', 'all', '--include-all')
    }
    elseif ($IncludeSQL) {
        $checkArgs += @('--extensions', 'sql')
    }
    if ($Mode -eq 'Private') { $checkArgs += '--enable-pls-check' }

    Write-Log "Running: azcmagent $($checkArgs -join ' ')" Info -NoCount
    Save-LogBuffer   # ensure ordering: header before the binary output
    try {
        $out = & $azcm @checkArgs 2>&1
        Add-Content -Path $LogFilePath -Value $out
        if ($LASTEXITCODE -eq 0) {
            Write-Log 'azcmagent check completed (exit 0).' OK
        }
        else {
            Write-Log "azcmagent check finished with exit $LASTEXITCODE." Fail
        }
    }
    catch {
        Write-Log "azcmagent check failed: $($_.Exception.Message)" Fail
    }
}
else {
    Write-Log 'azcmagent.exe not found - skipping check.' Warn
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
[void]$script:LogBuffer.Add('=' * 60)
Write-Log ("Summary: OK={0}  Fail={1}  Warn={2}  Mode={3}  Region={4}" -f `
        $script:Stats.OK, $script:Stats.Fail, $script:Stats.Warn, $Mode, $Region) Info -NoCount
Write-Log "Script finished at $(Get-Date -Format o)" Info -NoCount
Save-LogBuffer

# ---------------------------------------------------------------------------
# Results table (console + log)
# ---------------------------------------------------------------------------
$tableObjects = $script:Results | ForEach-Object { [pscustomobject]$_ }

Write-Host ''
Write-Host '=================== SUMMARY ===================' -ForegroundColor Cyan

$rowFormat = "{0,-5} {1,-55} {2,-26} {3,-8} {4,-5} {5,-5} {6,-12} {7,-9}"
Write-Host ($rowFormat -f 'Group', 'Endpoint', 'IP', 'Type', 'DNS', 'TCP', 'HTTP', 'Latency') -ForegroundColor Cyan
Write-Host ($rowFormat -f ('-' * 5), ('-' * 55), ('-' * 26), ('-' * 8), ('-' * 5), ('-' * 5), ('-' * 12), ('-' * 9)) -ForegroundColor DarkGray

foreach ($r in $tableObjects) {
    $hasFail = ($r.DNS -eq 'FAIL') -or ($r.TCP -eq 'FAIL') -or ($r.HTTP -like 'FAIL*')
    $hasWarn = ($r.DNS -eq 'WARN')
    $color   = if ($hasFail) { 'Red' } elseif ($hasWarn) { 'Yellow' } else { 'Green' }
    Write-Host ($rowFormat -f $r.Group, $r.Endpoint, $r.IP, $r.Type, $r.DNS, $r.TCP, $r.HTTP, $r.Latency) -ForegroundColor $color
}

Write-Host ''
Write-Host ("Totals: OK={0}  Fail={1}  Warn={2}  Mode={3}  Region={4}" -f `
        $script:Stats.OK, $script:Stats.Fail, $script:Stats.Warn, $Mode, $Region) -ForegroundColor Cyan

if ($script:EffectiveProxy) {
    Write-Host "Proxy used: $($script:EffectiveProxy)" -ForegroundColor DarkGray
}
else {
    Write-Host 'Proxy used: Direct (no proxy)' -ForegroundColor DarkGray
}

# Append table to the log file
$tableString = $tableObjects | Format-Table -AutoSize | Out-String
Add-Content -Path $LogFilePath -Value ''
Add-Content -Path $LogFilePath -Value '=================== SUMMARY ==================='
Add-Content -Path $LogFilePath -Value $tableString.TrimEnd()
Add-Content -Path $LogFilePath -Value ("Totals: OK={0}  Fail={1}  Warn={2}  Mode={3}  Region={4}" -f `
        $script:Stats.OK, $script:Stats.Fail, $script:Stats.Warn, $Mode, $Region)
if ($script:EffectiveProxy) {
    Add-Content -Path $LogFilePath -Value "Proxy used: $($script:EffectiveProxy)"
}
else {
    Add-Content -Path $LogFilePath -Value 'Proxy used: Direct (no proxy)'
}

Write-Host "`nFull log: $LogFilePath" -ForegroundColor Cyan
exit ([int]($script:Stats.Fail -gt 0))
