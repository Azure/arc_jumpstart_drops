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
$ProgressPreference    = 'SilentlyContinue'   # acelera Invoke-WebRequest e Test-NetConnection

$logDir = Split-Path -Path $LogFilePath -Parent
if ($logDir -and -not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
Set-Content -Path $LogFilePath -Value "Script started at $(Get-Date -Format o)" -Force

$script:Stats     = [ordered]@{ OK = 0; Fail = 0; Warn = 0 }
$script:LogBuffer = [System.Collections.ArrayList]::new()
$script:Results   = [System.Collections.ArrayList]::new()

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
        # PS 6+: espelha o agente, que IGNORA o proxy system-wide. Em PS 5.1 o
        # mesmo efeito e obtido neutralizando o DefaultWebProxy do .NET no setup.
        $params['NoProxy'] = $true
    }
    return Invoke-WebRequest @params
}

# ---------------------------------------------------------------------------
# Detecao e exibicao de proxy
# ---------------------------------------------------------------------------
$script:EffectiveProxy = $null

function Get-ProxyDiagnostics {
    Write-Log '=== DIAGNOSTICO DE PROXY ===' Info -NoCount
    [void]$script:LogBuffer.Add('')

    # Precedencia do proxy efetivo (usado nos testes HTTP deste script) — espelha
    # o comportamento do Azure Connected Machine agent no Windows:
    #   1) -ProxyUrl            (override explicito do operador)
    #   2) azcmagent proxy.url  (config do agente — TEM PRECEDENCIA sobre env vars)
    #   3) HTTPS_PROXY (env)    (system-wide)
    # O agente IGNORA o proxy system-wide do Windows (WinHTTP/WinINET); por isso o
    # WinHTTP abaixo e apenas REPORTADO, nunca aplicado automaticamente.
    # Ref: https://learn.microsoft.com/azure/azure-arc/servers/manage-agent-proxy-settings

    # 1) Parametro -ProxyUrl
    if ($ProxyUrl) {
        Write-Log "Proxy via parametro: $ProxyUrl" Info -NoCount
        $script:EffectiveProxy = $ProxyUrl
    }

    # WinHTTP (apenas informativo — o agente ignora o proxy system-wide)
    #    Nota: o parse do 'netsh' abaixo depende de Windows em INGLES. Em SO
    #    localizado (ex.: pt-BR) o regex pode nao casar e reportar 'Direct'
    #    mesmo havendo proxy configurado no WinHTTP.
    try {
        $winhttp = netsh winhttp show proxy 2>$null
        $winhttpText = ($winhttp | Out-String).Trim()
        if ($winhttpText -match 'Proxy Server\(s\)\s*:\s*(.+)') {
            $winhttpProxy = $Matches[1].Trim()
            Write-Log "WinHTTP Proxy: $winhttpProxy (informativo — o agente ignora o proxy system-wide)" Info -NoCount
        }
        else {
            Write-Log 'WinHTTP Proxy: Direct (sem proxy)' Info -NoCount
        }
        if ($winhttpText -match 'Bypass List\s*:\s*(.+)') {
            Write-Log "WinHTTP Bypass: $($Matches[1].Trim())" Info -NoCount
        }
    }
    catch {
        Write-Log "WinHTTP: nao foi possivel consultar ($($_.Exception.Message))" Warn
    }

    # 2) azcmagent config (proxy.url TEM PRECEDENCIA sobre HTTPS_PROXY)
    $azcm = Get-AzcmagentPath
    if ($azcm) {
        try {
            $proxyUrl = & $azcm config get proxy.url 2>$null
            if ($proxyUrl -and $proxyUrl.Trim()) {
                Write-Log "azcmagent proxy.url: $($proxyUrl.Trim())" Info -NoCount
                if (-not $script:EffectiveProxy) {
                    $script:EffectiveProxy = $proxyUrl.Trim()
                }
            }
            else {
                Write-Log 'azcmagent proxy.url: (nao configurado)' Info -NoCount
            }
            $bypass = & $azcm config get proxy.bypass 2>$null
            if ($bypass -and $bypass.Trim()) {
                Write-Log "azcmagent proxy.bypass: $($bypass.Trim())" Info -NoCount
            }
        }
        catch {
            Write-Log "azcmagent config: falha ao consultar ($($_.Exception.Message))" Warn
        }
    }

    # 3) Environment variables (verifica Machine -> Process -> User)
    $envProxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Machine')
    if (-not $envProxy) { $envProxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'Process') }
    if (-not $envProxy) { $envProxy = [Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'User') }
    $envNoProxy = [Environment]::GetEnvironmentVariable('NO_PROXY', 'Machine')
    if (-not $envNoProxy) { $envNoProxy = [Environment]::GetEnvironmentVariable('NO_PROXY', 'Process') }
    if (-not $envNoProxy) { $envNoProxy = [Environment]::GetEnvironmentVariable('NO_PROXY', 'User') }
    if ($envProxy) {
        Write-Log "Env HTTPS_PROXY: $envProxy" Info -NoCount
        if (-not $script:EffectiveProxy) {
            $script:EffectiveProxy = $envProxy
        }
    }
    else {
        Write-Log 'Env HTTPS_PROXY: (nao definido)' Info -NoCount
    }
    if ($envNoProxy) {
        Write-Log "Env NO_PROXY: $envNoProxy" Info -NoCount
    }

    if ($script:EffectiveProxy) {
        Write-Log "Proxy efetivo para testes HTTP: $($script:EffectiveProxy)" Info -NoCount
    }
    else {
        Write-Log 'Proxy efetivo: Direct (sem proxy — testes HTTP vao direto, como o agente)' Info -NoCount
    }

    [void]$script:LogBuffer.Add('')
}

# ---------------------------------------------------------------------------
# Deteccao automatica Public vs Private
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

    # RFC1918 + 100.64/10 (CGNAT, comum em redes corporativas)
    return ($bytes[0] -eq 10) -or
           ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or
           ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
           ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127)
}

function Resolve-ArcMode {
    Write-Log 'Detectando modo Arc (Public/Private)...' Info -NoCount

    # 1) Via azcmagent show -j
    $azcm = Get-AzcmagentPath
    if ($azcm) {
        try {
            $json = & $azcm show -j 2>$null | ConvertFrom-Json
            $pls = $json.privateLinkScope
            if ($pls) {
                Write-Log "azcmagent reporta privateLinkScope: $pls" Info -NoCount
                return 'Private'
            }
            else {
                # NAO conclui Public aqui: cai para o heuristico DNS abaixo. O
                # Private Link pode ser "via DNS" (Private DNS Zones) sem o agente
                # expor o PLS localmente em 'azcmagent show -j'.
                Write-Log 'azcmagent nao reporta privateLinkScope; confirmando via DNS...' Info -NoCount
            }
        }
        catch {
            Write-Log "Falha ao consultar azcmagent show -j: $($_.Exception.Message). Caindo para fallback DNS." Warn
        }
    }
    else {
        Write-Log 'azcmagent.exe nao encontrado. Usando fallback DNS.' Warn
    }

    # 2) Fallback: resolver gbl.his.arc.azure.com
    try {
        $dns = Resolve-DnsName -Name 'gbl.his.arc.azure.com' -Type A -ErrorAction Stop
        $ip  = ($dns | Where-Object IPAddress | Select-Object -First 1).IPAddress
        if (Test-IsPrivateIp -Ip $ip) {
            Write-Log "gbl.his.arc.azure.com resolve para IP privado ($ip) -> Private Link" Info -NoCount
            return 'Private'
        }
        else {
            Write-Log "gbl.his.arc.azure.com resolve para IP publico ($ip) -> Public" Info -NoCount
            return 'Public'
        }
    }
    catch {
        Write-Log 'Nao foi possivel resolver gbl.his.arc.azure.com - assumindo Public.' Warn
        return 'Public'
    }
}

# ---------------------------------------------------------------------------
# Detecao de modo e proxy
# ---------------------------------------------------------------------------
Get-ProxyDiagnostics

# Alinhamento com o agente: o Azure Connected Machine agent IGNORA o proxy
# system-wide do Windows (WinINET/WinHTTP). Se nenhum proxy efetivo foi
# detectado, neutralizamos o DefaultWebProxy do .NET (PS 5.1) para que os
# testes HTTP tambem vao direto. Em PS 6+ isso e feito via -NoProxy.
if (-not $script:EffectiveProxy -and $PSVersionTable.PSVersion.Major -lt 6) {
    try { [System.Net.WebRequest]::DefaultWebProxy = $null } catch { }
}

if ($Mode -eq 'Auto') {
    $Mode = Resolve-ArcMode
}
Write-Log "Modo selecionado: $Mode | Regiao: $Region" Info -NoCount

# Reset stats: fase de testes comeca aqui (detecao nao conta)
$script:Stats.OK   = 0
$script:Stats.Fail = 0
$script:Stats.Warn = 0

# ---------------------------------------------------------------------------
# Endpoints — organizados por grupo funcional
# ---------------------------------------------------------------------------

# Endpoints que PODEM resolver para IP privado via Azure Private Link Scope.
# Tudo que NAO esta nesta lista e sempre publico — nao gerar WARN em modo Private.
$canBePrivateEndpoints = @(
    'gbl.his.arc.azure.com'
    'agentserviceapi.guestconfiguration.azure.com'
    'dc.services.visualstudio.com'
    'global.handler.control.monitor.azure.com'
)

# Core Arc (obrigatorios) — alinhado a network-requirements do Connected Machine agent.
# Doc: https://learn.microsoft.com/azure/azure-arc/servers/network-requirements
$coreEndpoints = @(
    # AAD / Identity (sempre; Public)
    'login.windows.net'
    'login.microsoftonline.com'
    'pas.windows.net'

    # ARM (conexao/desconexao; Public salvo Resource Management Private Link)
    'management.azure.com'

    # Arc HIMDS (sempre; Private via PLS)
    'gbl.his.arc.azure.com'

    # Guest Configuration / gestao de extensoes (sempre; Private via PLS)
    'agentserviceapi.guestconfiguration.azure.com'

    # Instalacao/atualizacao do agente (Public)
    'packages.microsoft.com'
    'download.microsoft.com'

    # Telemetria (opcional; NAO usado em agentes 1.24+; Public)
    'dc.services.visualstudio.com'
)

# SQL endpoints (opcional via -IncludeSQL) — Arc-enabled SQL Server.
# Doc: network-requirements + sql/.../data-collection. Todos Public; TLS 1.2/1.3.
$sqlEndpoints = @()
if ($IncludeSQL) {
    $sqlEndpoints = @(
        # Data processing service + telemetria (extensoes a partir de mar/2024)
        "dataprocessingservice.$Region.arcdataservices.com"
        "telemetry.$Region.arcdataservices.com"
        # Legado: usado por extensoes ate 13/fev/2024
        "san-af-$Region-prod.azurewebsites.net"
        # Autenticacao Microsoft Entra do Arc SQL (Public). So necessario se usar
        # Entra auth; NAO e endpoint core do agente. Reachable direto, mas pode ser
        # bloqueado em proxy split-tunnel -> apenas DNS/TCP (sem HTTP probe).
        'graph.microsoft.com'
    )
}

# AMA endpoints (opcional via -IncludeAMA) — Azure Monitor Agent.
# Doc: azure-monitor-agent-network-configuration. Endpoints <workspace-id>.ods e
# <dce>.ingest.monitor exigem IDs especificos -> nao testaveis genericamente.
$amaEndpoints = @()
if ($IncludeAMA) {
    $amaEndpoints = @(
        'global.handler.control.monitor.azure.com'   # control service
        'global.prod.microsoftmetrics.com'           # metrics service
        "$Region.handler.control.monitor.azure.com"  # DCRs da regiao
        "$Region.monitoring.azure.com"               # custom metrics (opcional)
    )
}

# MDE endpoints (opcional via -IncludeMDE)
$mdeEndpoints = @()
if ($IncludeMDE) {
    $mdeEndpoints = @(
        'unitedstates.x.cp.wd.microsoft.com'
        'us-v20.events.data.microsoft.com'
    )
}

# WAC endpoints (opcional via -IncludeWAC)
$wacEndpoints = @()
if ($IncludeWAC) {
    $wacEndpoints = @(
        "$Region.service.waconazure.com"
        'pas.windows.net'
    )
}

# Endpoints que respondem HTTP (validacao L7 — 200/400/401/403/404 = reachable).
# NAO inclui graph.microsoft.com: e endpoint de Entra auth do Arc SQL (opcional) e
# costuma ser bloqueado em proxy split-tunnel; o proprio teste oficial de
# conectividade do Arc SQL valida apenas DPS + telemetria.
$httpProbeEndpoints = @(
    'login.windows.net'
    'login.microsoftonline.com'
    'management.azure.com'
)
if ($IncludeSQL) {
    # Alinhado ao teste oficial do Arc SQL: DPS espera 200; telemetria espera 401
    # (ambos tratados como reachable aqui).
    $httpProbeEndpoints += "dataprocessingservice.$Region.arcdataservices.com"
    $httpProbeEndpoints += "telemetry.$Region.arcdataservices.com"
}

# Mapeia grupo por endpoint para o sumario. Core tem PRECEDENCIA: se um endpoint
# aparece em mais de um grupo (ex.: pas.windows.net em Core e WAC), mantemos 'Core'.
$endpointGroupMap = @{}
foreach ($ep in $coreEndpoints) { $endpointGroupMap[$ep] = 'Core' }
foreach ($ep in $sqlEndpoints)  { if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = 'SQL' } }
foreach ($ep in $amaEndpoints)  { if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = 'AMA' } }
foreach ($ep in $mdeEndpoints)  { if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = 'MDE' } }
foreach ($ep in $wacEndpoints)  { if (-not $endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] = 'WAC' } }

# Dynamic allowlist (somente em modo publico; em PLS o trafego e via PE)
$dynamicEndpoints = @()
if ($Mode -eq 'Public') {
    try {
        Write-Log 'Buscando endpoints dinamicos do guestnotificationservice...' Info -NoCount
        $uri  = "https://guestnotificationservice.azure.com/urls/allowlist?api-version=2020-01-01&location=$Region"
        $resp = Invoke-WebRequestSafe -Uri $uri
        $dynamicEndpoints = @($resp.Content | ConvertFrom-Json) | Where-Object { $_ }
        if ($dynamicEndpoints.Count -gt 0) {
            $totalGNS = $dynamicEndpoints.Count

            # Filtrar: manter apenas endpoints primarios da regiao.
            # Namespaces primarios contem '<N>p-' (ex: 1p-, 2p-), secundarios contem '<N>s-'.
            # Extrair cluster IDs dos primarios e filtrar children por eles.
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
                        [void]$filteredGNS.Add($dep)   # sempre manter namespace-level
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
                    Write-Log "Endpoints dinamicos obtidos: $totalGNS total, $($filteredGNS.Count) primarios ($skipped secundarios filtrados)" OK
                }
                else {
                    Write-Log "Endpoints dinamicos obtidos: $totalGNS endpoint(s)" OK
                }
            }
            else {
                Write-Log "Endpoints dinamicos obtidos: $totalGNS endpoint(s)" OK
            }

            foreach ($dep in $dynamicEndpoints) {
                $endpointGroupMap[$dep] = 'GNS'
            }
        }
    }
    catch {
        # Allowlist dinamica e AUXILIAR: sua indisponibilidade nao deve derrubar o
        # exit code (WARN, nao FAIL). Comum ao forcar -Mode Public num host que, na
        # pratica, roteia o GNS via Private Link / firewall.
        Write-Log "Falha ao obter endpoints dinamicos (allowlist auxiliar): $($_.Exception.Message)" Warn
    }
}
else {
    Write-Log 'Modo Private: pulando consulta de allowlist publico.' Info -NoCount
}

$allEndpoints = @(
    $coreEndpoints + $sqlEndpoints + $amaEndpoints + $mdeEndpoints +
    $wacEndpoints + $dynamicEndpoints |
    Where-Object { $_ } |
    Select-Object -Unique
)

Write-Log "Total de endpoints a testar: $($allEndpoints.Count)" Info -NoCount
[void]$script:LogBuffer.Add('')

# ---------------------------------------------------------------------------
# Testes: DNS + TCP/443 (validacao de coerencia com o modo detectado)
# ---------------------------------------------------------------------------
foreach ($ep in $allEndpoints) {
    $ep = $ep.Trim()
    if (-not $ep) { continue }

    [void]$script:LogBuffer.Add('-' * 60)
    $group = if ($endpointGroupMap.ContainsKey($ep)) { $endpointGroupMap[$ep] } else { 'Dyn' }
    Add-Result -Endpoint $ep -Group $group

    # DNS (com 1 retry em falha transitoria, ex.: SERVFAIL ao resolver muitos nomes)
    $dns = $null
    $dnsErr = $null
    foreach ($attempt in 1..2) {
        try { $dns = Resolve-DnsName -Name $ep -ErrorAction Stop; $dnsErr = $null; break }
        catch { $dnsErr = $_; if ($attempt -lt 2) { Start-Sleep -Milliseconds 300 } }
    }
    if ($dnsErr) {
        # Endpoints dinamicos (GNS) sao AUXILIARES: uma falha de DNS neles vira WARN
        # (nao FAIL), pois um SERVFAIL transitorio ao resolver dezenas de nomes
        # 'servicebus' nao deve derrubar o exit code. Demais grupos permanecem FAIL.
        $existingD = $script:Results | Where-Object { $_.Endpoint -eq $ep }
        if ($group -eq 'GNS') {
            Write-Log "DNS WARN $ep - $($dnsErr.Exception.Message) (endpoint dinamico/auxiliar)" Warn
            if ($existingD) { $existingD.DNS = 'WARN' }
        }
        else {
            Write-Log "DNS FAIL $ep - $($dnsErr.Exception.Message)" Fail
            if ($existingD) { $existingD.DNS = 'FAIL' }
        }
        continue
    }

    # Preferir IPv4 (registro A): o Azure Private Link e a maioria dos endpoints
    # Arc sao resolvidos por A-record. Um AAAA (IPv6) publico pode coexistir com
    # o A privado; se escolhido, causa classificacao PUBLIC incorreta e testes
    # por um caminho IPv6 possivelmente inexistente/nao roteado.
    $rec = $dns | Where-Object { $_.Type -eq 'A' -and $_.IPAddress } | Select-Object -First 1
    if (-not $rec) { $rec = $dns | Where-Object IPAddress | Select-Object -First 1 }
    $ip   = $rec.IPAddress
    $kind = if (Test-IsPrivateIp -Ip $ip) { 'PRIVATE' } else { 'PUBLIC' }

    # Update result
    $existing = $script:Results | Where-Object { $_.Endpoint -eq $ep }
    if ($existing) { $existing.IP = $ip; $existing.Type = $kind }

    # Alerta de mismatch DNS x modo
    # Apenas endpoints em $canBePrivateEndpoints devem resolver para IP privado.
    # Todos os outros (AAD, ARM, CDN, SQL, AMA, MDE, WAC, GNS) sao sempre publicos.
    $canBePrivate = $canBePrivateEndpoints -contains $ep
    $mismatch = $false
    if ($Mode -eq 'Private' -and $kind -eq 'PUBLIC' -and $canBePrivate) {
        $mismatch = $true
    }
    elseif ($Mode -eq 'Public' -and $kind -eq 'PRIVATE') {
        $mismatch = $true
    }
    if ($mismatch) {
        Write-Log "DNS WARN $ep -> $ip [$kind] (esperado para modo $Mode era o oposto)" Warn
        $existing2 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
        if ($existing2) { $existing2.DNS = 'WARN' }
    }
    else {
        Write-Log "DNS OK   $ep -> $ip [$kind]" OK
        $existing2 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
        if ($existing2) { $existing2.DNS = 'OK' }
    }

    # TCP/443 (TcpClient com timeout — muito mais rapido que Test-NetConnection)
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
        Write-Log "TCP FAIL ${ep}:443 (timeout/recusado)" Fail
        if ($existing3) { $existing3.TCP = 'FAIL'; $existing3.Latency = 'timeout' }
    }
}

# ---------------------------------------------------------------------------
# Testes HTTP (401/403/400 sao considerados sucesso: endpoint exige auth)
# Detecta azcmagent proxy.bypass para pular HTTP tests em endpoints bypassados
# ---------------------------------------------------------------------------
$proxyBypassCategories = @()
$azcmPath = Get-AzcmagentPath
if ($azcmPath -and $script:EffectiveProxy) {
    try {
        $bypassRaw = & $azcmPath config get proxy.bypass 2>$null
        if ($bypassRaw -and $bypassRaw.Trim()) {
            $bypassClean = $bypassRaw.Trim().Trim('[', ']')
            $proxyBypassCategories = $bypassClean -split ',' | ForEach-Object { $_.Trim() }
        }
    }
    catch { }
}

# Mapa de categorias de bypass -> endpoints afetados (conforme doc oficial:
# https://learn.microsoft.com/azure/azure-arc/servers/manage-agent-proxy-settings).
# IMPORTANTE: 'graph.microsoft.com' NAO e coberto por nenhum bypass — o agente
# usa o proxy para ele; por isso ele NAO deve ser pulado nos testes HTTP.
# 'ArcData' e valido a partir do agente 1.36; em versoes anteriores os endpoints
# arcdataservices ficavam sob a categoria 'Arc'.
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
            [void]$httpBypassedEndpoints.Add($bep)
        }
    }
}

foreach ($ep in $httpProbeEndpoints) {
    $ep = $ep.Trim()
    if (-not $ep) { continue }

    # Se o endpoint esta no bypass do azcmagent e usamos proxy, HTTP test via proxy daria falso positivo
    if ($httpBypassedEndpoints -contains $ep) {
        Add-Result -Endpoint $ep -HTTP 'SKIP (bypass)'
        Write-Log "HTTP SKIP $ep (azcmagent proxy.bypass cobre este endpoint — agente nao usa proxy)" Info -NoCount
        continue
    }

    [void]$script:LogBuffer.Add('-' * 60)
    Add-Result -Endpoint $ep
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-WebRequestSafe -Uri "https://$ep" -TimeoutSec 10
        $sw.Stop()
        $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        Write-Log "HTTP OK  $ep -> $($resp.StatusCode) em ${elapsed}s" OK
        $existing4 = $script:Results | Where-Object { $_.Endpoint -eq $ep }
        if ($existing4) { $existing4.HTTP = "OK ($($resp.StatusCode))" }
    }
    catch {
        $sw.Stop()
        $code = $null
        if ($_.Exception.Response) {
            try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        }
        if ($code -in 400, 401, 403, 404) {
            Write-Log "HTTP OK  $ep -> $code (esperado sem auth/sem root handler)" OK
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
        # Doc oficial: '--extensions' e '--include-all' sao ORTOGONAIS.
        #   --extensions all -> endpoints de TODAS as extensoes (SQL, etc.)
        #   --include-all    -> casos de uso ESTENDIDOS (ex.: Windows Server PAYG)
        # Combinamos os dois para cobertura total.
        $checkArgs += @('--extensions', 'all', '--include-all')
    }
    elseif ($IncludeSQL) {
        $checkArgs += @('--extensions', 'sql')
    }
    if ($Mode -eq 'Private') { $checkArgs += '--enable-pls-check' }

    Write-Log "Executando: azcmagent $($checkArgs -join ' ')" Info -NoCount
    Save-LogBuffer   # garante ordem: cabecalho antes do output do binario
    try {
        $out = & $azcm @checkArgs 2>&1
        Add-Content -Path $LogFilePath -Value $out
        if ($LASTEXITCODE -eq 0) {
            Write-Log 'azcmagent check concluido (exit 0).' OK
        }
        else {
            Write-Log "azcmagent check terminou com exit $LASTEXITCODE." Fail
        }
    }
    catch {
        Write-Log "azcmagent check falhou: $($_.Exception.Message)" Fail
    }
}
else {
    Write-Log 'azcmagent.exe nao encontrado - pulando check.' Warn
}

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
[void]$script:LogBuffer.Add('=' * 60)
Write-Log ("Resumo: OK={0}  Fail={1}  Warn={2}  Modo={3}  Regiao={4}" -f `
        $script:Stats.OK, $script:Stats.Fail, $script:Stats.Warn, $Mode, $Region) Info -NoCount
Write-Log "Script finished at $(Get-Date -Format o)" Info -NoCount
Save-LogBuffer

# ---------------------------------------------------------------------------
# Tabela de resultados (console + log)
# ---------------------------------------------------------------------------
$tableObjects = $script:Results | ForEach-Object { [pscustomobject]$_ }

Write-Host ''
Write-Host '=================== SUMARIO ===================' -ForegroundColor Cyan

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
Write-Host ("Totais: OK={0}  Fail={1}  Warn={2}  Modo={3}  Regiao={4}" -f `
        $script:Stats.OK, $script:Stats.Fail, $script:Stats.Warn, $Mode, $Region) -ForegroundColor Cyan

if ($script:EffectiveProxy) {
    Write-Host "Proxy utilizado: $($script:EffectiveProxy)" -ForegroundColor DarkGray
}

# Append tabela ao arquivo de log
$tableString = $tableObjects | Format-Table -AutoSize | Out-String
Add-Content -Path $LogFilePath -Value ''
Add-Content -Path $LogFilePath -Value '=================== SUMARIO ==================='
Add-Content -Path $LogFilePath -Value $tableString.TrimEnd()
Add-Content -Path $LogFilePath -Value ("Totais: OK={0}  Fail={1}  Warn={2}  Modo={3}  Regiao={4}" -f `
        $script:Stats.OK, $script:Stats.Fail, $script:Stats.Warn, $Mode, $Region)

Write-Host "`nLog completo: $LogFilePath" -ForegroundColor Cyan
exit ([int]($script:Stats.Fail -gt 0))
