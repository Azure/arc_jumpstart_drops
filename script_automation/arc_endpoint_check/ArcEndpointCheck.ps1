#Requires -Version 5.1

<#
.SYNOPSIS
    Validates Azure Arc connectivity, DNS, TCP, HTTP, TLS, proxy, PKI bypass,
    and extension endpoints for Arc-enabled servers.

.DESCRIPTION
    Auto-detects EVERYTHING: region, connectivity mode (Public/Private/Gateway),
    proxy configuration, installed extensions, and regional endpoints.

    Connectivity modes supported (per Microsoft docs):
      - Public:  Direct internet or via forward proxy
      - Private: Azure Private Link Scope (PLS)
      - Gateway: Azure Arc Gateway (reduces endpoints to ~7 FQDNs)

    Validates:
      - Core Arc agent endpoints (HIMDS, GuestConfig, GNS, AAD, ARM)
      - Regional endpoints discovered from 'azcmagent check'
      - PKI/OCSP/CRL proxy bypass (detects "non-proxy request on proxy port")
      - TLS version (1.2+ required per Microsoft docs)
      - Extension endpoints based on installed extensions (auto-detected)
      - Arc Gateway URL when gateway mode is active

    Run with ZERO parameters for full auto-detection:
      PS> .\arcendpointcheck.ps1

.PARAMETER Region
    Azure region. Auto-detected from azcmagent if omitted.

.PARAMETER Mode
    Auto | Public | Private | Gateway. Default: Auto.

.PARAMETER ProxyUrl
    Override proxy URL. Auto-detected if omitted.

.PARAMETER LogFilePath
    Log file path. Default: C:\temp\Arclogfile.txt.

.PARAMETER SkipPKI
    Skips PKI/OCSP/CRL testing (not recommended).

.PARAMETER SkipExtensions
    Skips extension endpoint testing.

.PARAMETER CheckIncludeAll
    Makes 'azcmagent check' use '--extensions all --include-all'.

.EXAMPLE
    PS> .\arcendpointcheck.ps1
    Full auto: detects region, mode, proxy, extensions. Zero parameters needed.

.EXAMPLE
    PS> .\arcendpointcheck.ps1 -Region brazilsouth -Mode Private
    Forces region and mode override.

.EXAMPLE
    PS> .\arcendpointcheck.ps1 -Region eastus2 -Mode Private -ProxyUrl http://10.0.1.4:8443 -CheckIncludeAll
    Pre-onboarding: agent not installed. Specify region, mode, proxy, and test all extensions.

.NOTES
    Requires PowerShell 5.1+ on Windows.
    Ref: https://learn.microsoft.com/azure/azure-arc/network-requirements-consolidated
         https://learn.microsoft.com/azure/azure-arc/servers/arc-gateway
         https://learn.microsoft.com/azure/azure-arc/azure-firewall-explicit-proxy

.LINK
    https://azurearcjumpstart.com
#>

[CmdletBinding()]
param(
    [string]$Region = '',

    [ValidateSet('Auto', 'Public', 'Private', 'Gateway')]
    [string]$Mode = 'Auto',

    [string]$ProxyUrl,

    [string]$LogFilePath = "C:\temp\ArcEndpointCheck_$($env:COMPUTERNAME).txt",

    [switch]$SkipPKI,
    [switch]$SkipExtensions,
    [switch]$CheckIncludeAll
)

# =========================================================================
# SETUP
# =========================================================================
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$logDir = Split-Path -Path $LogFilePath -Parent
if ($logDir -and -not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
Set-Content -Path $LogFilePath -Value "ArcEndpointCheck started at $(Get-Date -Format o)" -Force

$script:Stats   = [ordered]@{ OK = 0; Fail = 0; Warn = 0 }
$script:Log      = [System.Collections.ArrayList]::new()
$script:Results  = [System.Collections.ArrayList]::new()
$script:Issues   = [System.Collections.ArrayList]::new()

# =========================================================================
# HELPERS
# =========================================================================

function Write-Banner {
    param([string]$T)
    $w = 74
    Write-Host ''
    Write-Host ('=' * $w) -ForegroundColor DarkCyan
    Write-Host "  $T" -ForegroundColor Cyan
    Write-Host ('=' * $w) -ForegroundColor DarkCyan
}

function Write-Section {
    param([string]$T)
    Write-Host ''
    Write-Host "  --- $T ---" -ForegroundColor DarkGray
}

function Write-Status {
    param([string]$Label, [string]$Value, [string]$Color = 'White')
    Write-Host ("  {0,-22} {1}" -f "${Label}:", $Value) -ForegroundColor $Color
}

function Test-IsValidProxyUri {
    param([string]$C)
    if (-not $C) { return $false }
    $p = $null
    return (
        [System.Uri]::TryCreate($C, [System.UriKind]::Absolute, [ref]$p) -and
        $p.Scheme -in @('http', 'https')
    )
}

function Log {
    param(
        [string]$Msg,
        [ValidateSet('Info', 'OK', 'Fail', 'Warn')][string]$Lv = 'Info',
        [switch]$NoCount
    )
    $line = "[$(Get-Date -Format HH:mm:ss)] [$($Lv.ToUpper().PadRight(4))] $Msg"
    [void]$script:Log.Add($line)
    Write-Verbose $line
    if (-not $NoCount) {
        if ($Lv -eq 'OK')   { $script:Stats.OK++ }
        if ($Lv -eq 'Fail') { $script:Stats.Fail++ }
        if ($Lv -eq 'Warn') { $script:Stats.Warn++ }
    }
}

function Add-Result {
    param(
        [string]$Endpoint, [string]$Group = 'Core', [string]$IP = '-',
        [string]$Type = '-', [string]$DNS = '-', [string]$TCP = '-',
        [string]$HTTP = '-', [string]$Latency = '-'
    )
    $ex = $script:Results | Where-Object { $_.Endpoint -eq $Endpoint }
    if ($ex) {
        if ($IP      -ne '-') { $ex.IP      = $IP }
        if ($Type    -ne '-') { $ex.Type    = $Type }
        if ($DNS     -ne '-') { $ex.DNS     = $DNS }
        if ($TCP     -ne '-') { $ex.TCP     = $TCP }
        if ($HTTP    -ne '-') { $ex.HTTP    = $HTTP }
        if ($Latency -ne '-') { $ex.Latency = $Latency }
    }
    else {
        [void]$script:Results.Add([ordered]@{
            Endpoint = $Endpoint; Group = $Group; IP = $IP; Type = $Type
            DNS = $DNS; TCP = $TCP; HTTP = $HTTP; Latency = $Latency
        })
    }
}

function Add-Issue {
    param([string]$Sev, [string]$Cat, [string]$Msg, [string]$Fix = '')
    [void]$script:Issues.Add([ordered]@{
        Severity = $Sev; Category = $Cat; Message = $Msg; Fix = $Fix
    })
}

function Save-Log {
    if ($script:Log.Count -gt 0) {
        Add-Content -Path $LogFilePath -Value $script:Log
        $script:Log.Clear()
    }
}

function Test-TcpPort {
    param([string]$H, [int]$P = 443, [int]$T = 5000)
    $c = [System.Net.Sockets.TcpClient]::new()
    try {
        $r = $c.BeginConnect($H, $P, $null, $null)
        if ($r.AsyncWaitHandle.WaitOne($T, $false) -and $c.Connected) {
            $c.EndConnect($r) | Out-Null
            return $true
        }
        return $false
    }
    catch { return $false }
    finally { $c.Close() }
}

function Invoke-HttpSafe {
    param([string]$Uri, [int]$Timeout = 10, [string]$UseProxy = '')
    $p = @{
        Uri = $Uri; Method = 'Get'; UseBasicParsing = $true
        TimeoutSec = $Timeout; ErrorAction = 'Stop'
    }
    $px = if ($UseProxy) { $UseProxy } else { $script:EffectiveProxy }
    if ($px) {
        $p['Proxy'] = $px
        $p['ProxyUseDefaultCredentials'] = $true
    }
    elseif ($PSVersionTable.PSVersion.Major -ge 6) {
        $p['NoProxy'] = $true
    }
    Invoke-WebRequest @p
}

function Get-AzcmagentPath {
    $c = Join-Path $env:ProgramFiles 'AzureConnectedMachineAgent\azcmagent.exe'
    if (Test-Path $c) { return $c }
    return $null
}

function Test-IsPrivateIp {
    param([string]$Ip)
    if (-not $Ip) { return $false }
    try { $b = ([System.Net.IPAddress]::Parse($Ip)).GetAddressBytes() }
    catch { return $false }
    return ($b[0] -eq 10) -or
           ($b[0] -eq 192 -and $b[1] -eq 168) -or
           ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
           ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127)
}

# =========================================================================
# 1. AGENT DETECTION (region, mode, gateway, extensions)
# =========================================================================

Write-Banner 'AZURE ARC ENDPOINT CHECK'
Write-Status 'Host' $env:COMPUTERNAME
Write-Status 'Time' (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

$script:EffectiveProxy = $null
$script:WinHttpProxy   = $null
$script:WinHttpBypass  = $null
$script:AgentJson      = $null
$script:GatewayUrl     = $null
$script:InstalledExts  = @()

$azcm = Get-AzcmagentPath
$script:PreOnboarding = (-not $azcm)
if ($azcm) {
    try { $script:AgentJson = & $azcm show -j 2>$null | ConvertFrom-Json } catch { }
}

# --- Pre-onboarding warning ---
if ($script:PreOnboarding) {
    Write-Host ''
    Write-Host '  ** PRE-ONBOARDING MODE **' -ForegroundColor Yellow
    Write-Host '  azcmagent not installed. Region, mode, and extensions' -ForegroundColor Yellow
    Write-Host '  cannot be auto-detected. Use parameters to override:' -ForegroundColor Yellow
    Write-Host '    -Region <region>  -Mode <Public|Private|Gateway>' -ForegroundColor DarkYellow
    Write-Host '    -CheckIncludeAll  (tests ALL extension endpoints)' -ForegroundColor DarkYellow
    Write-Host '    -ProxyUrl <url>   (if proxy is not yet in WinHTTP/env)' -ForegroundColor DarkYellow
    Write-Host ''
}

if ($azcm -and $script:AgentJson) {
    $agSt  = if ($script:AgentJson.PSObject.Properties['status']) { $script:AgentJson.status } else { $null }
    $agVer = if ($script:AgentJson.PSObject.Properties['agentVersion']) { $script:AgentJson.agentVersion } else { $null }
    $agParts = @('Installed')
    if ($agSt)  { $agParts += $agSt }
    if ($agVer) { $agParts += "v$agVer" }
    $agColor = if ($agSt -eq 'Connected') { 'Green' } elseif ($agSt -eq 'Disconnected') { 'Red' } else { 'Yellow' }
    Write-Status 'Agent' ($agParts -join ' | ') $agColor
}
elseif ($azcm) {
    Write-Status 'Agent' 'Installed (could not read status)' Yellow
}
else {
    Write-Status 'Agent' 'NOT INSTALLED (pre-onboarding)' Yellow
}

# --- Region ---
if (-not $Region) {
    if ($script:AgentJson -and $script:AgentJson.location) {
        $Region = $script:AgentJson.location
        Write-Status 'Region' "$Region (auto-detected)" Green
    }
    else {
        $Region = 'eastus2'
        Write-Status 'Region' "$Region (default - use -Region to override)" Yellow
    }
}
else {
    Write-Status 'Region' "$Region (specified)" White
}

# --- Mode ---
if ($Mode -eq 'Auto') {
    if ($script:AgentJson) {
        # Check for Gateway mode
        $gwUrl    = if ($script:AgentJson.PSObject.Properties['gatewayUrl'])    { $script:AgentJson.gatewayUrl }
                    elseif ($script:AgentJson.PSObject.Properties['gatewayurl']) { $script:AgentJson.gatewayurl }
                    else { $null }
        $connType = if ($script:AgentJson.PSObject.Properties['connectionType'])    { $script:AgentJson.connectionType }
                    elseif ($script:AgentJson.PSObject.Properties['connectiontype']) { $script:AgentJson.connectiontype }
                    else { $null }
        $plsVal   = if ($script:AgentJson.PSObject.Properties['privateLinkScope'])    { $script:AgentJson.privateLinkScope }
                    elseif ($script:AgentJson.PSObject.Properties['privatelinkscope']) { $script:AgentJson.privatelinkscope }
                    else { $null }

        if ($gwUrl -or $connType -eq 'gateway') {
            $Mode = 'Gateway'
            $script:GatewayUrl = $gwUrl
        }
        elseif ($plsVal) {
            $Mode = 'Private'
        }
        else {
            # DNS heuristic fallback
            try {
                $dns = Resolve-DnsName -Name 'gbl.his.arc.azure.com' -Type A -ErrorAction Stop
                $ip  = ($dns | Where-Object { $_.Type -eq 'A' -and $_.IPAddress } | Select-Object -First 1).IPAddress
                $Mode = if (Test-IsPrivateIp -Ip $ip) { 'Private' } else { 'Public' }
            }
            catch { $Mode = 'Public' }
        }
    }
    else {
        # No agent — use DNS heuristic to detect Private Link
        try {
            $dns = Resolve-DnsName -Name 'gbl.his.arc.azure.com' -Type A -ErrorAction Stop
            $ip  = ($dns | Where-Object { $_.Type -eq 'A' -and $_.IPAddress } | Select-Object -First 1).IPAddress
            $Mode = if (Test-IsPrivateIp -Ip $ip) { 'Private' } else { 'Public' }
        }
        catch { $Mode = 'Public' }
    }
}

$modeColor = switch ($Mode) {
    'Private' { 'Magenta' }
    'Gateway' { 'DarkYellow' }
    default   { 'Green' }
}
Write-Status 'Mode' $Mode $modeColor

if ($script:GatewayUrl) {
    Write-Status 'Gateway' $script:GatewayUrl DarkYellow
}

# --- Installed Extensions (auto-detect) ---
if (-not $SkipExtensions -and $azcm) {
    try {
        $extOut = & $azcm extension list 2>$null
        if ($extOut) {
            $extLines = $extOut | Out-String
            if ($extLines -match 'WindowsAgent\.SqlServer|LinuxAgent\.SqlServer|SqlServer')       { $script:InstalledExts += 'SQL' }
            if ($extLines -match 'AzureMonitor|AMA')                                              { $script:InstalledExts += 'AMA' }
            if ($extLines -match 'MDE|DefenderForServers|AzureDefender')                           { $script:InstalledExts += 'MDE' }
            if ($extLines -match 'AdminCenter')                                                   { $script:InstalledExts += 'WAC' }
            if ($extLines -match 'KeyVault')                                                      { $script:InstalledExts += 'KV' }
            if ($extLines -match 'HybridWorker|Automation')                                       { $script:InstalledExts += 'HRW' }
            if ($extLines -match 'ChangeTracking')                                                { $script:InstalledExts += 'CT' }
            if ($extLines -match 'GuestAttestation|WindowsAttestation|LinuxAttestation')           { $script:InstalledExts += 'GA' }
            if ($extLines -match 'WindowsPatchExtension|LinuxPatchExtension|UpdateManagement')     { $script:InstalledExts += 'UM' }
            if ($extLines -match 'CustomScript')                                                  { $script:InstalledExts += 'CS' }
            if ($extLines -match 'DependencyAgent')                                               { $script:InstalledExts += 'DA' }
            if ($extLines -match 'DefenderForSQL|AdvancedThreatProtection|MicrosoftDefenderForSQL') { $script:InstalledExts += 'DSQL' }
        }
    }
    catch { }
}

if ($script:InstalledExts.Count -gt 0) {
    Write-Status 'Extensions' ($script:InstalledExts -join ', ') White
}
else {
    if ($script:PreOnboarding) {
        if ($CheckIncludeAll) {
            Write-Status 'Extensions' '(all - pre-onboarding with -CheckIncludeAll)' DarkYellow
        }
        else {
            Write-Status 'Extensions' '(none - use -CheckIncludeAll to test all)' Yellow
        }
    }
    else {
        Write-Status 'Extensions' '(none detected)' DarkGray
    }
}

# =========================================================================
# 2. PROXY DETECTION
# =========================================================================

Write-Section 'Proxy Configuration'

# --- WinHTTP ---
try {
    $wh = netsh winhttp show proxy 2>$null | Out-String
    if ($wh -match 'Proxy Server\(s\)\s*:\s*(.+)|Servidor\(es\) Proxy\s*:\s*(.+)') {
        $script:WinHttpProxy = ($Matches[1], $Matches[2] | Where-Object { $_ } | Select-Object -First 1).Trim()
    }
    # Generic URL fallback for unrecognized locales (FR, DE, ES, JP, etc.)
    if (-not $script:WinHttpProxy -and $wh -notmatch 'Direct|direct|Direto|direto|Direkt' -and $wh -match '(https?://[^\s;]+)') {
        $script:WinHttpProxy = $Matches[1].Trim()
    }
    if ($wh -match 'Bypass List\s*:\s*(.+)|Lista de bypass\s*:\s*(.+)') {
        $script:WinHttpBypass = ($Matches[1], $Matches[2] | Where-Object { $_ } | Select-Object -First 1).Trim()
    }
}
catch { }

# --- Agent proxy ---
$agentProxy = $null
$agentBypass = $null
if ($azcm) {
    try {
        $raw = & $azcm config get proxy.url 2>$null | Out-String
        $raw = $raw.Trim()
        if (Test-IsValidProxyUri $raw) { $agentProxy = $raw }
        $agentBypass = (& $azcm config get proxy.bypass 2>$null | Out-String).Trim()
    }
    catch { }
}

# --- Env vars ---
$envProxy   = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Machine')
if (-not $envProxy) { $envProxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process') }
$envNoProxy = [Environment]::GetEnvironmentVariable('NO_PROXY', 'Machine')
if (-not $envNoProxy) { $envNoProxy = [Environment]::GetEnvironmentVariable('NO_PROXY', 'Process') }

# --- Effective proxy (precedence: -ProxyUrl > azcmagent > HTTPS_PROXY > WinHTTP) ---
if ($ProxyUrl -and (Test-IsValidProxyUri $ProxyUrl)) {
    $script:EffectiveProxy = $ProxyUrl
}
elseif ($agentProxy) {
    $script:EffectiveProxy = $agentProxy
}
elseif ($envProxy -and (Test-IsValidProxyUri $envProxy)) {
    $script:EffectiveProxy = $envProxy
}
elseif ($script:PreOnboarding -and $script:WinHttpProxy -and (Test-IsValidProxyUri "http://$($script:WinHttpProxy)")) {
    # Pre-onboarding: no agent proxy, fallback to WinHTTP if configured
    $whUri = if ($script:WinHttpProxy -match '^https?://') { $script:WinHttpProxy } else { "http://$($script:WinHttpProxy)" }
    if (Test-IsValidProxyUri $whUri) { $script:EffectiveProxy = $whUri }
}

# --- Upstream proxy (Gateway mode) ---
$upstreamProxy = $null
if ($script:AgentJson) {
    $upstreamProxy = if ($script:AgentJson.PSObject.Properties['upstreamProxy']) { $script:AgentJson.upstreamProxy }
                     elseif ($script:AgentJson.PSObject.Properties['upstreamproxy']) { $script:AgentJson.upstreamproxy }
                     else { $null }
}

# --- Display (pipe-delimited like azcmagent check) ---
$pFmt = "  {0,-18} | {1,-35} | {2,-22}"
Write-Host ($pFmt -f 'Source', 'Proxy', 'Used By') -ForegroundColor Cyan
Write-Host ("  {0,-18}-+-{1,-35}-+-{2,-22}" -f ('-' * 18), ('-' * 35), ('-' * 22)) -ForegroundColor DarkGray

$agentProxyLabel = if ($script:PreOnboarding) { 'N/A (not installed)' } elseif ($agentProxy) { $agentProxy } else { '(not set)' }
$rows = @(
    , @('WinHTTP (OS)',  $(if ($script:WinHttpProxy) { $script:WinHttpProxy } else { 'Direct' }),  'SCHANNEL/OCSP/CRL')
    , @('azcmagent',    $agentProxyLabel,                                                          'Arc Agent')
    , @('HTTPS_PROXY',  $(if ($envProxy) { $envProxy } else { '(not set)' }),                       'Extensions')
)
if ($upstreamProxy) {
    $rows += , @('Upstream Proxy', $upstreamProxy, 'Gateway chain')
}
foreach ($r in $rows) {
    $c = if ($r[1] -match 'not set|Direct|N/A') { 'DarkGray' } else { 'White' }
    Write-Host ($pFmt -f $r[0], $r[1], $r[2]) -ForegroundColor $c
}
if ($script:EffectiveProxy) {
    Write-Host ''
    Write-Status 'Effective proxy' $script:EffectiveProxy Green
}

# --- Gateway + proxy.bypass warning ---
if ($Mode -eq 'Gateway' -and $agentBypass) {
    Add-Issue -Sev 'WARN' -Cat 'Gateway' `
        -Msg 'proxy.bypass is configured but NOT supported in Gateway mode' `
        -Fix 'Run: azcmagent config clear proxy.bypass'
}

# Neutralize .NET DefaultWebProxy for PS 5.1 when no proxy
if (-not $script:EffectiveProxy -and $PSVersionTable.PSVersion.Major -lt 6) {
    try { [System.Net.WebRequest]::DefaultWebProxy = $null } catch { }
}

Log "Region=$Region Mode=$Mode Proxy=$($script:EffectiveProxy) Gateway=$($script:GatewayUrl)" Info -NoCount

# =========================================================================
# 3. TLS VERSION CHECK
# =========================================================================

Write-Section 'TLS Validation'
# Azure Arc requires TLS 1.2 or 1.3 ONLY.
# Required cipher suites:
#   TLS 1.3: TLS_AES_256_GCM_SHA384, TLS_AES_128_GCM_SHA256
#   TLS 1.2: TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384, TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
# SQL Arc endpoints (*.arcdataservices.com) require TLS 1.2/1.3 — Server 2012 (non-R2) NOT supported.
# Ref: https://learn.microsoft.com/azure/azure-arc/servers/troubleshoot-networking#windows-tls-configuration-issues

$tlsOk = $false
try {
    $osVer = [System.Environment]::OSVersion.Version
    $osBuild = $osVer.Build
    $osCaption = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    if (-not $osCaption) { $osCaption = "Windows $($osVer.Major).$($osVer.Minor) Build $osBuild" }
    Write-Status 'OS' $osCaption DarkGray

    # --- 1. SCHANNEL Registry Check ---
    $schBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
    $tls12Disabled = $false
    $tls12Path = "$schBase\TLS 1.2\Client"
    if (Test-Path $tls12Path) {
        $enVal = (Get-ItemProperty -Path $tls12Path -Name 'Enabled' -EA SilentlyContinue).Enabled
        $dbVal = (Get-ItemProperty -Path $tls12Path -Name 'DisabledByDefault' -EA SilentlyContinue).DisabledByDefault
        if ($enVal -eq 0) { $tls12Disabled = $true }
        if ($dbVal -eq 1 -and $enVal -ne 1) { $tls12Disabled = $true }
    }

    # TLS 1.3 support (Server 2022+ / Build 20348+)
    $has13 = $false
    $tls13Path = "$schBase\TLS 1.3\Client"
    if (Test-Path $tls13Path) {
        $en13 = (Get-ItemProperty -Path $tls13Path -Name 'Enabled' -EA SilentlyContinue).Enabled
        if ($en13 -ne 0) { $has13 = $true }
    }
    if ($osVer.Major -ge 10 -and $osBuild -ge 20348) { $has13 = $true }

    # OS era check
    $isServer2012NonR2 = ($osVer.Major -eq 6 -and $osVer.Minor -eq 2)  # 6.2 = Server 2012 / Win8
    $isModernOS = ($osVer.Major -gt 6) -or ($osVer.Major -eq 6 -and $osVer.Minor -ge 3)  # 6.3+ = 2012R2+

    # --- 2. Real TLS 1.2 Handshake Test ---
    $tlsHandshakeOk = $false
    $negotiatedProto = ''
    try {
        # Force .NET to use TLS 1.2 for this test
        $savedProto = [System.Net.ServicePointManager]::SecurityProtocol
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $testReq = [System.Net.HttpWebRequest]::Create('https://login.microsoftonline.com')
        $testReq.Timeout = 10000
        $testReq.Method = 'HEAD'
        if ($script:EffectiveProxy) {
            $testReq.Proxy = [System.Net.WebProxy]::new($script:EffectiveProxy)
            $testReq.Proxy.UseDefaultCredentials = $true
        } elseif ($PSVersionTable.PSVersion.Major -lt 6) {
            $testReq.Proxy = $null
        }
        $testResp = $testReq.GetResponse()
        $testResp.Close()
        $tlsHandshakeOk = $true
        $negotiatedProto = 'TLS 1.2'
        [System.Net.ServicePointManager]::SecurityProtocol = $savedProto
    }
    catch {
        try { [System.Net.ServicePointManager]::SecurityProtocol = $savedProto } catch { }
        # If TLS 1.2 fails, the OS may not support it
    }

    # --- 3. Cipher Suite Check ---
    $requiredCiphers12 = @(
        'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'
        'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
    )
    $requiredCiphers13 = @(
        'TLS_AES_256_GCM_SHA384'
        'TLS_AES_128_GCM_SHA256'
    )
    $cipherOk = $true
    $missingCiphers = @()
    try {
        $sysCiphers = (Get-TlsCipherSuite -ErrorAction SilentlyContinue).Name
        if ($sysCiphers) {
            foreach ($rc in $requiredCiphers12) {
                if ($sysCiphers -notcontains $rc) { $missingCiphers += $rc; $cipherOk = $false }
            }
        }
        # Get-TlsCipherSuite may not exist on older OS (Server 2012/2012R2)
    }
    catch {
        # Get-TlsCipherSuite not available — skip cipher check (older OS)
        $cipherOk = $true
    }

    # --- 4. .NET Strong Crypto ---
    $strongCrypto = $false
    $regPath64 = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
    $regPath32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'
    foreach ($rp in @($regPath64, $regPath32)) {
        if (Test-Path $rp) {
            $sc = (Get-ItemProperty -Path $rp -Name 'SchUseStrongCrypto' -EA SilentlyContinue).SchUseStrongCrypto
            if ($sc -eq 1) { $strongCrypto = $true }
        }
    }

    # --- Display Results ---
    if ($tls12Disabled) {
        Write-Status 'SCHANNEL TLS 1.2' 'DISABLED in registry' Red
        Add-Issue -Sev 'CRITICAL' -Cat 'TLS' `
            -Msg 'TLS 1.2 is disabled in SCHANNEL registry. Azure Arc requires TLS 1.2+.' `
            -Fix 'https://learn.microsoft.com/azure/azure-arc/servers/troubleshoot-networking#windows-tls-configuration-issues'
    }
    elseif ($tlsHandshakeOk) {
        $tlsLabel = if ($has13) { 'TLS 1.2 + 1.3' } else { 'TLS 1.2' }
        Write-Status 'TLS Handshake' "$tlsLabel verified (live test passed)" Green
        $tlsOk = $true
    }
    elseif ($isModernOS) {
        Write-Status 'TLS SCHANNEL' 'TLS 1.2 enabled (OS default, handshake test failed)' Yellow
        $tlsOk = $true
    }
    else {
        Write-Status 'TLS' 'Could not verify TLS 1.2 - check SCHANNEL config' Yellow
        Add-Issue -Sev 'HIGH' -Cat 'TLS' `
            -Msg 'Cannot verify TLS 1.2 support. Azure Arc requires TLS 1.2+.' `
            -Fix 'https://learn.microsoft.com/azure/azure-arc/servers/troubleshoot-networking#windows-tls-configuration-issues'
    }

    # Cipher suites
    if (-not $cipherOk -and $missingCiphers.Count -gt 0) {
        Write-Status 'Cipher Suites' "MISSING: $($missingCiphers -join ', ')" Red
        Add-Issue -Sev 'HIGH' -Cat 'TLS Ciphers' `
            -Msg "Required cipher suites missing: $($missingCiphers -join ', ')" `
            -Fix 'Enable GCM cipher suites via Group Policy or PowerShell Enable-TlsCipherSuite'
    }
    elseif ($missingCiphers.Count -eq 0 -and $cipherOk) {
        Write-Status 'Cipher Suites' 'Required GCM suites present' Green
    }

    # .NET StrongCrypto
    if ($strongCrypto) {
        Write-Status '.NET StrongCrypto' 'Enabled' Green
    }
    else {
        Write-Status '.NET StrongCrypto' 'NOT set (recommended for PS 5.1 / .NET apps)' Yellow
    }

    # Server 2012 (non-R2) + SQL Arc warning
    if ($isServer2012NonR2 -and ($script:InstalledExts -contains 'SQL' -or $CheckIncludeAll)) {
        Write-Status 'SQL Arc TLS' 'Server 2012 (non-R2) NOT supported for SQL Arc telemetry' Red
        Add-Issue -Sev 'HIGH' -Cat 'SQL TLS' `
            -Msg 'Windows Server 2012 (non-R2) does not support TLS 1.2 for *.arcdataservices.com endpoints.' `
            -Fix 'Upgrade to Server 2012 R2+ for SQL Server enabled by Azure Arc.'
    }
}
catch {
    Write-Status 'TLS' "Check error: $($_.Exception.Message)" Yellow
    $tlsOk = $true
}
Log "TLS check: OK=$tlsOk handshake=$tlsHandshakeOk ciphers=$cipherOk strongCrypto=$strongCrypto" $(if ($tlsOk) { 'OK' } else { 'Fail' })

# =========================================================================
# 4. PKI/OCSP/CRL BYPASS VALIDATION
# =========================================================================

$pkiEndpoints = @(
    'oneocsp.microsoft.com'       # OCSP primary
    'crl.microsoft.com'           # CRL Microsoft root
    'crl2.microsoft.com'          # CRL Microsoft intermediate
    'crl3.digicert.com'           # CRL DigiCert
    'crl4.digicert.com'           # CRL DigiCert alt
    'ocsp.digicert.com'           # OCSP DigiCert
    'ctldl.windowsupdate.com'     # Certificate Trust List
    'www.microsoft.com'           # PKI AIA chain
    'caissuers.microsoft.com'     # CA Issuers (AIA)
    'login.live.com'              # Live ID cert validation
)

$pkiWildcardCovers = @{
    '.microsoft.com'      = @('oneocsp.microsoft.com', 'crl.microsoft.com', 'crl2.microsoft.com',
                              'www.microsoft.com', 'caissuers.microsoft.com')
    '.digicert.com'       = @('crl3.digicert.com', 'crl4.digicert.com', 'ocsp.digicert.com')
    '.live.com'           = @('login.live.com')
    '.ocsp.microsoft.com' = @('oneocsp.microsoft.com')
    '.ocsp.digicert.com'  = @('ocsp.digicert.com')
}

function Test-PkiBypassCoverage {
    if (-not $script:WinHttpProxy) { return @() }

    $byList = @()
    if ($script:WinHttpBypass) {
        # WinHTTP uses *.domain.com format; normalize to .domain.com for matching
        $byList += $script:WinHttpBypass -split ';' |
            ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ } |
            ForEach-Object { if ($_ -match '^\*\.([a-z])') { $_.Substring(1) } else { $_ } }
    }
    if ($envNoProxy) {
        $byList += $envNoProxy -split ',' |
            ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
    }
    if ($byList.Count -eq 0) { return $pkiEndpoints }

    $covered = [System.Collections.ArrayList]::new()
    foreach ($wc in $pkiWildcardCovers.Keys) {
        if ($byList -contains $wc.ToLower()) {
            foreach ($ep in $pkiWildcardCovers[$wc]) {
                if ($covered -notcontains $ep.ToLower()) { [void]$covered.Add($ep.ToLower()) }
            }
        }
    }

    $uncovered = @()
    foreach ($ep in $pkiEndpoints) {
        $lo = $ep.ToLower()
        if ($byList -contains $lo) { continue }
        if ($covered -contains $lo) { continue }
        $matched = $false
        foreach ($be in $byList) {
            if ($be.StartsWith('.') -and $lo.EndsWith($be)) { $matched = $true; break }
        }
        if (-not $matched) { $uncovered += $ep }
    }
    return $uncovered
}

if (-not $SkipPKI -and $script:WinHttpProxy) {
    Write-Section 'PKI/OCSP/CRL Proxy Bypass'
    $uncPki = Test-PkiBypassCoverage
    if ($uncPki.Count -eq 0) {
        Write-Host '  All PKI endpoints covered by bypass list' -ForegroundColor Green
    }
    else {
        Write-Host '  PKI endpoints MISSING from proxy bypass (TLS will fail):' -ForegroundColor Red
        $bFmt = "    {0,-9} | {1}"
        Write-Host ($bFmt -f 'Status', 'Endpoint') -ForegroundColor Gray
        Write-Host ("    {0,-9}-+-{1}" -f ('-' * 9), ('-' * 40)) -ForegroundColor DarkGray
        foreach ($ep in $uncPki) {
            Write-Host ($bFmt -f 'MISSING', $ep) -ForegroundColor Red
            Log "PKI bypass MISSING: $ep" Fail
        }
        Add-Issue -Sev 'CRITICAL' -Cat 'PKI Bypass' `
            -Msg "$($uncPki.Count) PKI endpoint(s) not in proxy bypass" `
            -Fix "Add to GPO NO_PROXY: $($uncPki -join ',')"
    }
}

# =========================================================================
# 5. ENDPOINT DEFINITIONS
# =========================================================================

# Reset stats for test phase
$script:Stats.OK = 0
$script:Stats.Fail = 0
$script:Stats.Warn = 0

# Endpoints eligible for Private Link resolution
$canBePrivate = [System.Collections.ArrayList]@(
    'gbl.his.arc.azure.com'
    'agentserviceapi.guestconfiguration.azure.com'
    'dc.services.visualstudio.com'
    'global.handler.control.monitor.azure.com'
)

# --- Core endpoints (always tested) ---
$coreEps = [System.Collections.ArrayList]@(
    'login.windows.net'
    'login.microsoftonline.com'
    "$Region.login.microsoft.com"
    'pas.windows.net'
    'management.azure.com'
    'gbl.his.arc.azure.com'
    'agentserviceapi.guestconfiguration.azure.com'
    'packages.microsoft.com'
    'download.microsoft.com'
    'dc.services.visualstudio.com'
)

# GNS global (Public/Gateway modes)
if ($Mode -in 'Public', 'Gateway') {
    [void]$coreEps.Add('guestnotificationservice.azure.com')
}

# Gateway URL
if ($script:GatewayUrl) {
    try {
        $gwFqdn = ([System.Uri]$script:GatewayUrl).Host
        if ($gwFqdn) { [void]$coreEps.Add($gwFqdn) }
    }
    catch {
        $gwFqdn = $script:GatewayUrl -replace 'https?://', '' -replace '/.*', ''
        if ($gwFqdn) { [void]$coreEps.Add($gwFqdn) }
    }
}

# --- Extension endpoints (auto-detected) ---
$extEps = @{}

# SQL Server
if ($script:InstalledExts -contains 'SQL' -or $CheckIncludeAll) {
    $extEps['SQL'] = @(
        "dataprocessingservice.$Region.arcdataservices.com"
        "telemetry.$Region.arcdataservices.com"
        "san-af-$Region-prod.azurewebsites.net"
        'graph.microsoft.com'
    )
}

# Defender for SQL (separate from MDE)
if ($script:InstalledExts -contains 'DSQL' -or $CheckIncludeAll) {
    if (-not $extEps.ContainsKey('SQL')) { $extEps['SQL'] = @() }
    $extEps['SQL'] += @("defender-for-databases.$Region.arcdataservices.com")
}

# AMA (Azure Monitor Agent) + Dependency Agent
if ($script:InstalledExts -contains 'AMA' -or $script:InstalledExts -contains 'DA' -or $CheckIncludeAll) {
    $extEps['AMA'] = @(
        'global.handler.control.monitor.azure.com'
        'global.prod.microsoftmetrics.com'
        "$Region.handler.control.monitor.azure.com"
        "$Region.monitoring.azure.com"
    )
}

# MDE (Microsoft Defender for Endpoint)
if ($script:InstalledExts -contains 'MDE' -or $CheckIncludeAll) {
    $extEps['MDE'] = @(
        'unitedstates.x.cp.wd.microsoft.com'
        'us-v20.events.data.microsoft.com'
        'winatp-gw-cus3.microsoft.com'
    )
}

# WAC (Windows Admin Center)
if ($script:InstalledExts -contains 'WAC' -or $CheckIncludeAll) {
    $extEps['WAC'] = @("$Region.service.waconazure.com")
}

# Key Vault extension
if ($script:InstalledExts -contains 'KV' -or $CheckIncludeAll) {
    $extEps['KV'] = @('*.vault.azure.net')
}

# Hybrid Runbook Worker
if ($script:InstalledExts -contains 'HRW' -or $CheckIncludeAll) {
    $extEps['HRW'] = @(
        '*.azure-automation.net'
        '*.agentsvc.azure-automation.net'
    )
}

# Update Manager
if ($script:InstalledExts -contains 'UM' -or $CheckIncludeAll) {
    $extEps['UM'] = @("$Region.monitoring.azure.com")
}

# Guest Attestation
if ($script:InstalledExts -contains 'GA' -or $CheckIncludeAll) {
    $extEps['GA'] = @('*.attest.azure.net')
}

# -SkipExtensions overrides -CheckIncludeAll (user explicitly asked to skip)
if ($SkipExtensions -and $extEps.Count -gt 0) {
    $extEps = @{}
    Log 'Extension endpoints skipped (-SkipExtensions)' Info -NoCount
}

# =========================================================================
# 6. DISCOVER REGIONAL ENDPOINTS (azcmagent check)
# =========================================================================
# Regional Arc endpoints use unpredictable abbreviations (e.g. eus2, brs, ncus).
# Instead of guessing, we parse 'azcmagent check' output to discover the actual
# endpoints the agent uses.

Write-Section 'Endpoint Discovery (azcmagent check)'

$script:AzcmagentCheckExit = $null
$discoveredEps = @()

if ($azcm) {
    $checkArgs = @('check', '--location', $Region, '--cloud', 'AzureCloud')
    if ($CheckIncludeAll) {
        $checkArgs += @('--extensions', 'all', '--include-all')
    }
    elseif ($script:InstalledExts -contains 'SQL') {
        $checkArgs += @('--extensions', 'sql')
    }
    if ($Mode -eq 'Private') { $checkArgs += '--enable-pls-check' }

    Write-Host "  azcmagent $($checkArgs -join ' ')" -ForegroundColor Gray
    try {
        $out = & $azcm @checkArgs 2>&1
        $script:AzcmagentCheckExit = $LASTEXITCODE
        Save-Log
        Add-Content -Path $LogFilePath -Value $out

        # Parse pipe-delimited output to extract endpoint FQDNs
        foreach ($line in $out) {
            $s = "$line".Trim()
            if ($s -match '\|\s*https?://([^\s|/]+)') {
                $fqdn = $Matches[1]
                if ($fqdn -and $fqdn -notmatch '^(Use Case|Endpoint)') {
                    $discoveredEps += $fqdn
                }
            }
        }
        $discoveredEps = $discoveredEps | Select-Object -Unique

        if ($script:AzcmagentCheckExit -eq 0) {
            Write-Host "  PASSED - discovered $($discoveredEps.Count) endpoints" -ForegroundColor Green
        }
        else {
            Write-Host "  FAILED (exit $($script:AzcmagentCheckExit)) - discovered $($discoveredEps.Count) endpoints" -ForegroundColor Red
            Add-Issue -Sev 'HIGH' -Cat 'Agent Check' `
                -Msg "azcmagent check failed (exit $($script:AzcmagentCheckExit))" `
                -Fix 'Review azcmagent check output in log file'
        }
    }
    catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host '  azcmagent not found - using DNS-based regional endpoint discovery' -ForegroundColor Yellow

    # --- Regional endpoint fallback (no agent) ---
    # his.arc.azure.com uses unpredictable abbreviations per region.
    # We try a known map + DNS probing to discover the correct FQDN.
    $regionAbbrevMap = @{
        'eastus'='eus'; 'eastus2'='eus2'; 'westus'='wus'; 'westus2'='wus2'; 'westus3'='wus3'
        'centralus'='cus'; 'northcentralus'='ncus'; 'southcentralus'='scus'; 'westcentralus'='wcus'
        'canadacentral'='cac'; 'canadaeast'='cae'
        'brazilsouth'='brs'; 'brazilsoutheast'='brse'
        'northeurope'='neu'; 'westeurope'='weu'
        'uksouth'='uks'; 'ukwest'='ukw'
        'francecentral'='frc'; 'francesouth'='frs'
        'germanywestcentral'='gwc'; 'switzerlandnorth'='szn'; 'switzerlandwest'='szw'
        'norwayeast'='noe'; 'norwaywest'='now'; 'swedencentral'='sec'
        'australiaeast'='aue'; 'australiasoutheast'='ause'
        'eastasia'='ea'; 'southeastasia'='sea'
        'japaneast'='jpe'; 'japanwest'='jpw'
        'koreacentral'='krc'; 'koreasouth'='krs'
        'centralindia'='inc'; 'southindia'='ins'; 'westindia'='inw'
        'southafricanorth'='san'; 'southafricawest'='saw'
        'uaenorth'='uan'; 'uaecentral'='uac'
        'qatarcentral'='qac'; 'polandcentral'='plc'; 'italynorth'='itn'
    }

    # Try HIS endpoint: abbreviation first, then full name
    $hisCandidates = @()
    $rLower = $Region.ToLower()
    if ($regionAbbrevMap.ContainsKey($rLower)) {
        $hisCandidates += "$($regionAbbrevMap[$rLower]).his.arc.azure.com"
    }
    $hisCandidates += "$Region.his.arc.azure.com"

    foreach ($hc in $hisCandidates) {
        try {
            $null = Resolve-DnsName -Name $hc -ErrorAction Stop
            $discoveredEps += $hc
            Write-Host "    Discovered: $hc" -ForegroundColor Green
            break
        }
        catch { }
    }

    # GuestConfiguration always uses full region name with -gas suffix
    $gcCandidate = "$Region-gas.guestconfiguration.azure.com"
    try {
        $null = Resolve-DnsName -Name $gcCandidate -ErrorAction Stop
        $discoveredEps += $gcCandidate
        Write-Host "    Discovered: $gcCandidate" -ForegroundColor Green
    }
    catch { }

    if ($discoveredEps.Count -gt 0) {
        Write-Host "  Discovered $($discoveredEps.Count) regional endpoint(s) via DNS" -ForegroundColor Green
    }
    else {
        Write-Host '  No regional endpoints discovered (verify -Region parameter)' -ForegroundColor Yellow
        Add-Issue -Sev 'WARN' -Cat 'Discovery' `
            -Msg "Could not discover regional endpoints for region '$Region'" `
            -Fix 'Verify -Region parameter or install azcmagent first'
    }
}

# Merge discovered endpoints into core list (avoid duplicates)
foreach ($dep in $discoveredEps) {
    if ($coreEps -notcontains $dep) { [void]$coreEps.Add($dep) }
    # Mark PLS-eligible patterns
    if ($dep -match 'his\.arc\.azure\.com|guestconfiguration\.azure\.com') {
        if ($canBePrivate -notcontains $dep) { [void]$canBePrivate.Add($dep) }
    }
}

# --- Build final endpoint group map ---
$endpointGroupMap = @{}
foreach ($ep in $coreEps) { $endpointGroupMap[$ep] = 'Core' }
foreach ($grp in $extEps.Keys) {
    foreach ($ep in $extEps[$grp]) {
        if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = $grp }
    }
}
if (-not $SkipPKI) {
    foreach ($ep in $pkiEndpoints) {
        if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = 'PKI' }
    }
}

# --- Dynamic GNS allowlist (Public mode only) ---
$dynamicEps = @()
if ($Mode -eq 'Public') {
    try {
        $uri  = "https://guestnotificationservice.azure.com/urls/allowlist?api-version=2020-01-01&location=$Region"
        $resp = Invoke-HttpSafe -Uri $uri
        $dynamicEps = @($resp.Content | ConvertFrom-Json) | Where-Object { $_ }
        if ($dynamicEps.Count -gt 0) {
            # Filter to primary namespaces only
            $pids = [System.Collections.ArrayList]::new()
            foreach ($d in $dynamicEps) {
                if ($d -match '^azgn-.+\dp-.+?-(\w+)\.servicebus') { [void]$pids.Add($Matches[1]) }
            }
            if ($pids.Count -gt 0) {
                $filtered = [System.Collections.ArrayList]::new()
                foreach ($d in $dynamicEps) {
                    if ($d -match '^azgn-') { [void]$filtered.Add($d) }
                    else {
                        foreach ($cid in $pids) {
                            if ($d -like "*$cid*") { [void]$filtered.Add($d); break }
                        }
                    }
                }
                $dynamicEps = @($filtered)
            }
            foreach ($d in $dynamicEps) { $endpointGroupMap[$d] = 'GNS' }
        }
    }
    catch {
        Log "GNS dynamic allowlist failed: $($_.Exception.Message)" Warn
    }
}

# --- Build combined testable list ---
$allTestable = @()
foreach ($ep in $coreEps) { $allTestable += $ep }
foreach ($grp in $extEps.Keys) {
    foreach ($ep in $extEps[$grp]) { $allTestable += $ep }
}
$allTestable += $dynamicEps
if (-not $SkipPKI) { $allTestable += $pkiEndpoints }

# Separate wildcards (informational, not testable) from concrete FQDNs
$wildcardEps = @($allTestable | Where-Object { $_ -match '^\*\.' } | Select-Object -Unique)
$allTestable = @($allTestable | Where-Object { $_ -notmatch '^\*\.' } | Where-Object { $_ } | Select-Object -Unique)

# --- HTTP probe endpoints ---
$httpProbeEps = @('login.windows.net', 'login.microsoftonline.com', 'management.azure.com')
if ($extEps.ContainsKey('SQL')) {
    $httpProbeEps += "dataprocessingservice.$Region.arcdataservices.com"
    $httpProbeEps += "telemetry.$Region.arcdataservices.com"
}

# --- Agent proxy.bypass => skip HTTP for bypassed endpoints ---
$httpBypassedEps = [System.Collections.ArrayList]::new()
if ($azcm -and $script:EffectiveProxy) {
    $bypassCats = @()
    try {
        $bRaw = (& $azcm config get proxy.bypass 2>$null | Out-String).Trim()
        if ($bRaw) {
            $bypassCats = $bRaw.Trim('[', ']') -split ',' |
                ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }
    }
    catch { }

    $catMap = @{
        'AAD'     = @('login.windows.net', 'login.microsoftonline.com', 'pas.windows.net')
        'ARM'     = @('management.azure.com')
        'Arc'     = @('gbl.his.arc.azure.com', 'agentserviceapi.guestconfiguration.azure.com')
        'ArcData' = @("dataprocessingservice.$Region.arcdataservices.com",
                      "telemetry.$Region.arcdataservices.com")
        'AMA'     = @('global.handler.control.monitor.azure.com',
                      "$Region.handler.control.monitor.azure.com")
    }
    foreach ($cat in $bypassCats) {
        if ($catMap.ContainsKey($cat)) {
            foreach ($ep in $catMap[$cat]) {
                if ($httpBypassedEps -notcontains $ep) { [void]$httpBypassedEps.Add($ep) }
            }
        }
    }
}

# =========================================================================
# 7. ENDPOINT TESTS: DNS + TCP/443
# =========================================================================

Write-Banner "TESTING $($allTestable.Count) ENDPOINTS"

$pi = 0
foreach ($ep in $allTestable) {
    $ep = $ep.Trim()
    if (-not $ep) { continue }
    $pi++

    $grp = if ($endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] } else { 'Core' }
    Add-Result -Endpoint $ep -Group $grp

    $pct = [math]::Round(($pi / $allTestable.Count) * 100)
    $epShort = if ($ep.Length -gt 56) { $ep.Substring(0, 53) + '...' } else { $ep }
    Write-Host ("`r  [{0,3}%] {1,-58}" -f $pct, $epShort) -NoNewline -ForegroundColor Gray

    # --- DNS ---
    $dns = $null
    $dnsErr = $null
    foreach ($a in 1..2) {
        try {
            $dns = Resolve-DnsName -Name $ep -ErrorAction Stop
            $dnsErr = $null
            break
        }
        catch {
            $dnsErr = $_
            if ($a -lt 2) { Start-Sleep -Milliseconds 300 }
        }
    }

    if ($dnsErr) {
        $lv = if ($grp -eq 'GNS') { 'Warn' } else { 'Fail' }
        Log "DNS $lv $ep - $($dnsErr.Exception.Message)" $lv
        $rr = $script:Results | Where-Object { $_.Endpoint -eq $ep }
        if ($rr) { $rr.DNS = $lv.ToUpper() }
        if ($lv -eq 'Fail') {
            Add-Issue -Sev 'HIGH' -Cat 'DNS' -Msg "Cannot resolve $ep" -Fix 'Check DNS/firewall'
        }
        continue
    }

    $rec = $dns | Where-Object { $_.Type -eq 'A' -and $_.IPAddress } | Select-Object -First 1
    if (-not $rec) { $rec = $dns | Where-Object IPAddress | Select-Object -First 1 }
    $ip   = $rec.IPAddress
    $kind = if (Test-IsPrivateIp $ip) { 'PRIV' } else { 'PUB' }

    $rr = $script:Results | Where-Object { $_.Endpoint -eq $ep }
    if ($rr) { $rr.IP = $ip; $rr.Type = $kind }

    $cbp = $canBePrivate -contains $ep
    $mm  = ($Mode -eq 'Private' -and $kind -eq 'PUB' -and $cbp) -or
           ($Mode -eq 'Public'  -and $kind -eq 'PRIV')
    if ($mm) {
        Log "DNS WARN $ep -> $ip [$kind] mode mismatch" Warn
        $rr2 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
        if ($rr2) { $rr2.DNS = 'WARN' }
    }
    else {
        Log "DNS OK $ep -> $ip" OK
        $rr2 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
        if ($rr2) { $rr2.DNS = 'OK' }
    }

    # --- TCP/443 ---
    # Note: TCP tests L3/L4 reachability directly (not via proxy).
    # In explicit proxy setups, this validates the network path through the firewall.
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = Test-TcpPort -H $ep -P 443 -T 5000
    $sw.Stop()
    $ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 0)

    $rr3 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
    if ($ok) {
        Log "TCP OK ${ep}:443 (${ms}ms)" OK
        if ($rr3) { $rr3.TCP = 'OK'; $rr3.Latency = "${ms}ms" }
    }
    else {
        Log "TCP FAIL ${ep}:443" Fail
        if ($rr3) { $rr3.TCP = 'FAIL'; $rr3.Latency = 'timeout' }
        Add-Issue -Sev 'HIGH' -Cat 'TCP' -Msg "Cannot connect to ${ep}:443" -Fix 'Check firewall/proxy rules'
    }
}
Write-Host ''   # Clear progress line

# =========================================================================
# 8. HTTP TESTS + PKI PROBE
# =========================================================================

foreach ($ep in $httpProbeEps) {
    $ep = $ep.Trim()
    if (-not $ep) { continue }
    if ($httpBypassedEps -contains $ep) {
        Add-Result -Endpoint $ep -HTTP 'SKIP'
        Log "HTTP SKIP $ep (bypass)" Info -NoCount
        continue
    }
    try {
        $resp = Invoke-HttpSafe -Uri "https://$ep" -Timeout 10
        Log "HTTP OK $ep -> $($resp.StatusCode)" OK
        Add-Result -Endpoint $ep -HTTP "OK($($resp.StatusCode))"
    }
    catch {
        $code = $null
        if ($_.Exception.Response) {
            try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        }
        if ($code -in 400, 401, 403, 404) {
            Log "HTTP OK $ep -> $code" OK
            Add-Result -Endpoint $ep -HTTP "OK($code)"
        }
        else {
            Log "HTTP FAIL $ep" Fail
            Add-Result -Endpoint $ep -HTTP 'FAIL'
            Add-Issue -Sev 'MEDIUM' -Cat 'HTTP' -Msg "HTTP failed: $ep" -Fix 'Check proxy/firewall app rules'
        }
    }
}

# PKI HTTP probe — tests the REAL path SCHANNEL will use:
#   If oneocsp.microsoft.com is in bypass → test DIRECT (no proxy)
#   If NOT in bypass → test via WinHTTP proxy (likely fails on explicit proxy)
if (-not $SkipPKI -and $script:WinHttpProxy) {
    $uncPkiNow = Test-PkiBypassCoverage
    $ocspBypassed = $uncPkiNow -notcontains 'oneocsp.microsoft.com'

    if ($ocspBypassed) {
        # Endpoint is in bypass — SCHANNEL will connect DIRECT, not via proxy
        try {
            $probeParams = @{
                Uri = 'http://oneocsp.microsoft.com'
                Method = 'Get'; UseBasicParsing = $true
                TimeoutSec = 5; ErrorAction = 'Stop'
            }
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                $probeParams['NoProxy'] = $true
            }
            else {
                $savedWP = [System.Net.WebRequest]::DefaultWebProxy
                [System.Net.WebRequest]::DefaultWebProxy = $null
            }
            $resp = Invoke-WebRequest @probeParams
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                [System.Net.WebRequest]::DefaultWebProxy = $savedWP
            }
            Log "PKI probe OK direct (bypass active)" OK
            Add-Result -Endpoint 'oneocsp.microsoft.com' -HTTP "OK($($resp.StatusCode))"
        }
        catch {
            try { if ($PSVersionTable.PSVersion.Major -lt 6) { [System.Net.WebRequest]::DefaultWebProxy = $savedWP } } catch { }
            # OCSP responders return 4xx on bare GET — any HTTP response = reachable
            $code = $null
            try {
                if ($_.Exception -and $_.Exception.Response) {
                    $code = [int]$_.Exception.Response.StatusCode
                }
            } catch { }
            if ($code -and $code -ge 200 -and $code -lt 600) {
                Log "PKI probe OK direct -> $code (bypass active)" OK
                Add-Result -Endpoint 'oneocsp.microsoft.com' -HTTP "OK($code)"
            }
            else {
                $msg = $_.Exception.Message
                Log "PKI probe FAIL direct: $msg" Fail
                Add-Result -Endpoint 'oneocsp.microsoft.com' -HTTP 'FAIL'
                Add-Issue -Sev 'HIGH' -Cat 'PKI Direct' `
                    -Msg 'OCSP unreachable via direct path (bypass active but no route)' `
                    -Fix 'Ensure firewall network/application rules allow direct HTTP:80 to PKI endpoints'
            }
        }
    }
    else {
        # Endpoint NOT in bypass — SCHANNEL sends via proxy (will likely fail on explicit proxy)
        try {
            $resp = Invoke-HttpSafe -Uri 'http://oneocsp.microsoft.com' -Timeout 5 -UseProxy $script:WinHttpProxy
            Log "PKI probe OK via WinHTTP proxy" OK
            Add-Result -Endpoint 'oneocsp.microsoft.com' -HTTP "OK($($resp.StatusCode))"
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -match '407') {
                Log "PKI probe: 407 proxy auth" Warn
                Add-Result -Endpoint 'oneocsp.microsoft.com' -HTTP 'WARN'
            }
            else {
                Log "PKI probe FAIL via proxy: $msg" Fail
                Add-Result -Endpoint 'oneocsp.microsoft.com' -HTTP 'FAIL'
                Add-Issue -Sev 'CRITICAL' -Cat 'PKI Proxy' `
                    -Msg 'OCSP unreachable via WinHTTP proxy (non-proxy request on proxy port)' `
                    -Fix 'Add PKI endpoints to proxy bypass (GPO NO_PROXY)'
            }
        }
    }
}

# azcmagent check result (already ran during discovery)
if ($null -ne $script:AzcmagentCheckExit) {
    if ($script:AzcmagentCheckExit -eq 0) { Log 'azcmagent check: exit 0' OK }
    else { Log "azcmagent check: exit $($script:AzcmagentCheckExit)" Fail }
}
elseif (-not $azcm) {
    Log 'azcmagent not found - skipping check' Warn
}

Save-Log

# =========================================================================
# 9. RESULTS TABLE
# =========================================================================

Write-Banner 'RESULTS'

$tbl = $script:Results | ForEach-Object { [pscustomobject]$_ }

# Sort by group priority
$grps = $tbl | Group-Object Group | Sort-Object @{ Expression = {
    switch ($_.Name) {
        'Core' { 0 }; 'PKI' { 1 }; 'SQL' { 2 }; 'AMA' { 3 }; 'MDE' { 4 }
        'WAC'  { 5 }; 'KV'  { 6 }; 'HRW' { 7 }; 'UM'  { 8 }; 'GA'  { 9 }
        'GNS'  { 10 }; default { 11 }
    }
} }

# Pipe-delimited table (azcmagent check style)
$hf = "  {0,-5} | {1,-50} | {2,-16} | {3,-4} | {4,-9} | {5,-7}"
Write-Host ($hf -f 'Group', 'Endpoint', 'IP', 'Type', 'Result', 'Latency') -ForegroundColor Cyan
Write-Host ("  {0,-5}-+-{1,-50}-+-{2,-16}-+-{3,-4}-+-{4,-9}-+-{5,-7}" -f `
    ('-' * 5), ('-' * 50), ('-' * 16), ('-' * 4), ('-' * 9), ('-' * 7)) -ForegroundColor DarkGray

foreach ($g in $grps) {
    foreach ($r in $g.Group) {
        $dnsOk  = $r.DNS  -notin @('FAIL', 'WARN', '-')
        $tcpOk  = $r.TCP  -notin @('FAIL', '-')
        $httpOk = ($r.HTTP -eq '-') -or ($r.HTTP -like 'OK*') -or ($r.HTTP -eq 'SKIP')
        $fail   = ($r.DNS -eq 'FAIL') -or ($r.TCP -eq 'FAIL') -or ($r.HTTP -like 'FAIL*')
        $warn   = ($r.DNS -eq 'WARN') -or ($r.HTTP -like 'WARN*')

        # Compose result column (mimics azcmagent: Reachable / Unreachable / Warning)
        if ($fail) {
            $detail = @()
            if ($r.DNS -eq 'FAIL') { $detail += 'DNS' }
            if ($r.TCP -eq 'FAIL') { $detail += 'TCP' }
            if ($r.HTTP -like 'FAIL*') { $detail += 'HTTP' }
            $result = "FAIL($($detail -join ','))"
        }
        elseif ($warn) {
            $result = 'Warning'
        }
        elseif ($r.HTTP -eq 'SKIP') {
            $result = 'Reachable*'
        }
        else {
            $result = 'Reachable'
        }

        $c = if ($fail) { 'Red' } elseif ($warn) { 'Yellow' } else { 'Green' }
        Write-Host ($hf -f $r.Group, $r.Endpoint, $r.IP, $r.Type, $result, $r.Latency) -ForegroundColor $c
    }
}

# Wildcard endpoints (informational)
if ($wildcardEps.Count -gt 0) {
    Write-Host ''
    $wFmt = "  {0,-5} | {1,-50} | {2}"
    Write-Host ($wFmt -f 'Group', 'Wildcard Endpoint', 'Note') -ForegroundColor DarkGray
    Write-Host ("  {0,-5}-+-{1,-50}-+-{2}" -f ('-' * 5), ('-' * 50), ('-' * 30)) -ForegroundColor DarkGray
    foreach ($w in $wildcardEps) {
        $wg = if ($endpointGroupMap.ContainsKey($w)) { $endpointGroupMap[$w] } else { '-' }
        Write-Host ($wFmt -f $wg, $w, 'Requires firewall rule (not testable)') -ForegroundColor DarkGray
    }
}

# =========================================================================
# 10. ISSUES
# =========================================================================

if ($script:Issues.Count -gt 0) {
    Write-Banner "ISSUES ($($script:Issues.Count))"
    $iFmt = "  {0,-3} | {1,-8} | {2,-12} | {3}"
    Write-Host ($iFmt -f '#', 'Severity', 'Category', 'Message') -ForegroundColor Cyan
    Write-Host ("  {0,-3}-+-{1,-8}-+-{2,-12}-+-{3}" -f ('-' * 3), ('-' * 8), ('-' * 12), ('-' * 50)) -ForegroundColor DarkGray
    $ix = 0
    foreach ($iss in $script:Issues) {
        $ix++
        $sc = switch ($iss.Severity) {
            'CRITICAL' { 'Red' }; 'HIGH' { 'Red' }
            'MEDIUM' { 'Yellow' }; 'WARN' { 'Yellow' }
            default { 'Gray' }
        }
        Write-Host ($iFmt -f $ix, $iss.Severity, $iss.Category, $iss.Message) -ForegroundColor $sc
        if ($iss.Fix) {
            Write-Host ("  {0,-3} | {1,-8} | {2,-12} | Fix: {3}" -f '', '', '', $iss.Fix) -ForegroundColor DarkCyan
        }
    }
}

# =========================================================================
# 11. FINAL SUMMARY
# =========================================================================

Write-Host ''
Write-Host ('=' * 74) -ForegroundColor DarkCyan

$fc = $script:Stats.Fail
$wc = $script:Stats.Warn
$oc = $script:Stats.OK
$ic = $script:Issues.Count

# Only CRITICAL/HIGH issues cause FAIL; WARN/MEDIUM issues cause WARN status but exit 0
$critIssues = @($script:Issues | Where-Object { $_.Severity -in @('CRITICAL', 'HIGH') })
$hasFail    = ($fc -gt 0) -or ($critIssues.Count -gt 0)
$hasWarn    = ($wc -gt 0) -or ($ic -gt $critIssues.Count)
$summColor  = if ($hasFail) { 'Red' } elseif ($hasWarn) { 'Yellow' } else { 'Green' }
$statusText = if ($hasFail) { 'FAIL' } elseif ($hasWarn) { 'WARN' } else { 'PASS' }

$gwTag = if ($script:GatewayUrl) { ' [GW]' } else { '' }
$preTag = if ($script:PreOnboarding) { ' [PRE-ONBOARDING]' } else { '' }
Write-Host ("  STATUS: {0}  |  OK:{1} Fail:{2} Warn:{3} Issues:{4}  |  {5} {6}{7}{8}" -f `
    $statusText, $oc, $fc, $wc, $ic, $Mode, $Region, $gwTag, $preTag) -ForegroundColor $summColor

if ($script:InstalledExts.Count -gt 0) {
    Write-Host "  Extensions: $($script:InstalledExts -join ', ')" -ForegroundColor DarkGray
}
if ($script:EffectiveProxy) {
    Write-Host "  Proxy: $($script:EffectiveProxy)" -ForegroundColor DarkGray
}
Write-Host "  Log: $LogFilePath" -ForegroundColor DarkGray
Write-Host ('=' * 74) -ForegroundColor DarkCyan

# --- Append to log file ---
$ts = $tbl | Format-Table -AutoSize | Out-String
Add-Content -Path $LogFilePath -Value ''
Add-Content -Path $LogFilePath -Value '=================== RESULTS ==================='
Add-Content -Path $LogFilePath -Value $ts.TrimEnd()
Add-Content -Path $LogFilePath -Value ("Status: $statusText | OK=$oc Fail=$fc Warn=$wc Issues=$ic | $Mode $Region$gwTag")

if ($ic -gt 0) {
    Add-Content -Path $LogFilePath -Value ''
    Add-Content -Path $LogFilePath -Value '=================== ISSUES ==================='
    foreach ($iss in $script:Issues) {
        Add-Content -Path $LogFilePath -Value "[$($iss.Severity)] $($iss.Category): $($iss.Message)"
        if ($iss.Fix) { Add-Content -Path $LogFilePath -Value "  Fix: $($iss.Fix)" }
    }
}

exit ([int]$hasFail)
