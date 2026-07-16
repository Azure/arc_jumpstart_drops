---
type: docs
title: "Azure Arc Connectivity Check"
linkTitle: "Azure Arc Connectivity Check"
weight: 1
description: >
    Validate Azure Arc agent connectivity, TLS configuration, proxy bypass, and
    extension endpoints across Public, Private Link, and Gateway deployments —
    with full auto-detection and pre-onboarding support.
---

## Overview

This script validates network connectivity for Azure Arc-enabled servers across all
three connectivity modes: **Public**, **Private Link**, and **Gateway**. It auto-detects
region, connectivity mode, proxy configuration, installed extensions, and regional
endpoints — run it with **zero parameters** on any machine where the agent is installed.

For **pre-onboarding** (agent not yet installed), pass `-Region`, `-Mode`, and
`-CheckIncludeAll` to validate the network before deploying.

### What it validates

| Area | Details |
| ---- | ------- |
| **Core endpoints** | AAD, ARM, HIMDS, GuestConfig, GNS, packages, downloads |
| **Regional endpoints** | Discovered via `azcmagent check` or DNS-based abbreviation map (40+ regions) |
| **Extension endpoints** | SQL, AMA, MDE, WAC, Key Vault, Hybrid Worker, Change Tracking, Update Manager, Guest Attestation, Dependency Agent, Defender for SQL — auto-detected from installed extensions |
| **DNS + TCP/443** | Resolution, private vs public IP classification, latency measurement |
| **HTTP probes** | Layer-7 reachability through proxy for key endpoints |
| **TLS 1.2/1.3** | SCHANNEL registry, live handshake test, cipher suite validation (GCM), .NET StrongCrypto |
| **PKI/OCSP/CRL bypass** | Detects missing proxy bypass for certificate validation endpoints (Azure Firewall explicit proxy "non-proxy request on proxy port" scenario) |
| **Proxy configuration** | WinHTTP, `azcmagent proxy.url`, `HTTPS_PROXY`, `proxy.bypass` categories, upstream proxy (Gateway) |
| **Dynamic GNS allowlist** | Queries `guestnotificationservice.azure.com` for region-specific ServiceBus endpoints (Public mode) |
| **Arc Gateway** | Validates gateway URL, detects `proxy.bypass` misconfiguration in Gateway mode |

### Key improvements over earlier versions

- **Zero parameters needed** — auto-detects everything from `azcmagent show -j`,
  `azcmagent check`, `azcmagent extension list`, WinHTTP, and environment variables.
- **Three connectivity modes** — Public, Private Link, and Gateway (with gateway URL
  validation and upstream proxy display).
- **Pre-onboarding mode** — works without `azcmagent` installed; uses DNS-based regional
  endpoint discovery with a built-in abbreviation map for 40+ Azure regions.
- **PKI bypass validation** — detects when WinHTTP proxy is configured but PKI/OCSP/CRL
  endpoints are missing from the bypass list (root cause of Azure Firewall explicit proxy
  TLS failures).
- **TLS validation** — SCHANNEL registry check, live TLS 1.2 handshake, cipher suite
  verification, .NET StrongCrypto, and Server 2012 (non-R2) SQL Arc incompatibility
  warning.
- **Extension auto-detection** — discovers 12 extension types from `azcmagent extension list`
  and tests their specific endpoints.
- **Pipe-delimited output** — `azcmagent check` style tabular format with consolidated
  `Result` column (Reachable / FAIL(DNS,TCP) / Warning).
- **Smart exit codes** — `0` = PASS or WARN-only, `1` = FAIL (CRITICAL/HIGH issues).
  WARN-level issues (e.g., Gateway bypass, Discovery) do not cause exit 1.
- **Locale-independent** WinHTTP proxy detection with URL-based fallback for non-EN/PT
  systems.

## Prerequisites

- **Windows PowerShell 5.1 or later** (the script uses `netsh`, `Resolve-DnsName`, and
  `azcmagent.exe`).
- Outbound network connectivity to Azure Arc endpoints (directly, via proxy, or via
  Gateway).
- *(Optional)* The **Azure Connected Machine agent** (`azcmagent.exe`). Without it the
  script runs in pre-onboarding mode — DNS/TCP/HTTP/TLS tests still execute, but
  `azcmagent check` and extension auto-detection are skipped.
- Run from an **elevated PowerShell** session for the most complete results.

## Getting Started

Download [arcendpointcheck.ps1](./arcendpointcheck.ps1) and run it on the server where
the Azure Arc agent is (or will be) installed.

**You never edit the script.** Everything is controlled by parameters:

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `-Region` | Azure region (e.g., `eastus2`, `brazilsouth`). Auto-detected from `azcmagent show` if omitted. | *(auto-detect or `eastus2`)* |
| `-Mode` | `Auto`, `Public`, `Private`, or `Gateway`. In `Auto`, the script checks `azcmagent show` for Private Link Scope or Gateway URL, then falls back to a DNS heuristic (`gbl.his.arc.azure.com` → private IP = Private). `Private` automatically adds `--enable-pls-check` to `azcmagent check`. | `Auto` |
| `-ProxyUrl` | Explicit HTTP/HTTPS proxy (e.g., `http://10.0.1.4:8443`). If omitted, auto-detects in order: `azcmagent proxy.url` → `HTTPS_PROXY` env var → WinHTTP (pre-onboarding only). | *(auto-detect)* |
| `-LogFilePath` | Path to the log file. Includes hostname automatically. | `C:\temp\ArcEndpointCheck_<HOSTNAME>.txt` |
| `-SkipPKI` | Skips PKI/OCSP/CRL bypass validation and endpoint testing (not recommended). | *(off)* |
| `-SkipExtensions` | Skips all extension endpoint testing. Overrides `-CheckIncludeAll`. | *(off)* |
| `-CheckIncludeAll` | Tests ALL extension endpoints (even without agent detection). Also makes `azcmagent check` use `--extensions all --include-all`. Ideal for pre-onboarding validation. | *(off)* |

## Using the Script

### Post-onboarding (agent installed)

```powershell
# Full auto — zero parameters needed
.\arcendpointcheck.ps1

# Force a specific region
.\arcendpointcheck.ps1 -Region brazilsouth

# Force Private Link mode with verbose logging
.\arcendpointcheck.ps1 -Mode Private -Verbose

# Test all extension endpoints (including not yet installed)
.\arcendpointcheck.ps1 -CheckIncludeAll
```

### Pre-onboarding (agent not installed)

```powershell
# Minimum: region + test all extensions
.\arcendpointcheck.ps1 -Region eastus2 -CheckIncludeAll

# Full pre-onboarding with proxy + Private Link
.\arcendpointcheck.ps1 -Region eastus2 -Mode Private -ProxyUrl http://10.0.1.4:8443 -CheckIncludeAll

# Public mode, specific region, skip PKI (firewall team will handle)
.\arcendpointcheck.ps1 -Region brazilsouth -Mode Public -SkipPKI -CheckIncludeAll
```

### Azure Firewall explicit proxy scenarios

```powershell
# Validate connectivity through explicit proxy (auto-detected from azcmagent/WinHTTP)
.\arcendpointcheck.ps1

# Override proxy URL if not yet configured in azcmagent
.\arcendpointcheck.ps1 -ProxyUrl http://10.0.1.4:8443
```

## Output Format

The script produces pipe-delimited tables matching the `azcmagent check` style:

### Header

```
==========================================================================
  AZURE ARC ENDPOINT CHECK
==========================================================================
  Host:                  SQLNODE1
  Time:                  2026-07-03 17:38:51
  Agent:                 Installed | Connected | v1.65.03439.3010
  Region:                eastus2 (auto-detected)
  Mode:                  Private
  Extensions:            SQL, AMA, MDE, WAC, CT, UM, DSQL
```

### Proxy Configuration

```
  Source             | Proxy                               | Used By
  -------------------+-------------------------------------+-----------------------
  WinHTTP (OS)       | http://10.0.1.4:8443                | SCHANNEL/OCSP/CRL
  azcmagent          | http://10.0.1.4:8443                | Arc Agent
  HTTPS_PROXY        | http://10.0.1.4:8443                | Extensions
```

### Results Table

```
  Group | Endpoint                                           | IP               | Type | Result    | Latency
  ------+----------------------------------------------------+------------------+------+-----------+--------
  Core  | login.windows.net                                  | 20.190.173.132   | PUB  | Reachable | 24ms
  Core  | gbl.his.arc.azure.com                              | 10.1.0.4         | PRIV | Reachable | 305ms
  PKI   | oneocsp.microsoft.com                              | 204.79.197.203   | PUB  | Reachable | 33ms
  SQL   | dataprocessingservice.eastus2.arcdataservices.com   | 72.153.30.41     | PUB  | Reachable | 130ms
```

**Result values:**

| Result | Meaning |
| ------ | ------- |
| `Reachable` | DNS + TCP + HTTP all passed |
| `Reachable*` | DNS + TCP passed, HTTP skipped (proxy.bypass active) |
| `FAIL(DNS)` | DNS resolution failed |
| `FAIL(TCP)` | TCP/443 connection timed out |
| `FAIL(DNS,TCP)` | Both DNS and TCP failed |
| `FAIL(HTTP)` | HTTP probe failed (proxy/firewall blocking) |
| `Warning` | Mode mismatch (e.g., Private mode but endpoint resolves to public IP) |

### Issues Table

```
  #   | Severity | Category     | Message
  ----+----------+--------------+---------------------------------------------------
  1   | CRITICAL | PKI Bypass   | 2 PKI endpoint(s) not in proxy bypass
      |          |              | Fix: Add to GPO NO_PROXY: crl4.digicert.com
```

### Summary Line

```
  STATUS: PASS  |  OK:74 Fail:0 Warn:0 Issues:0  |  Private eastus2
```

Tags appended when applicable: `[GW]` for Gateway mode, `[PRE-ONBOARDING]` when agent
is not installed.

## Exit Codes

| Code | Status | Meaning |
| ---- | ------ | ------- |
| `0` | PASS | All checks passed |
| `0` | WARN | Only WARN/MEDIUM severity issues (e.g., Gateway bypass, Discovery) |
| `1` | FAIL | At least one CRITICAL or HIGH severity issue, or a DNS/TCP test failure |

## Auto-Detection Logic

The script automatically detects the following without any parameters:

| What | Source | Fallback |
| ---- | ------ | -------- |
| **Region** | `azcmagent show -j` → `.location` | Default `eastus2` (with warning) |
| **Mode** | `azcmagent show -j` → `.privateLinkScope` / `.gatewayUrl` / `.connectionType` | DNS heuristic: `gbl.his.arc.azure.com` → private IP = Private |
| **Proxy** | `azcmagent config get proxy.url` → `HTTPS_PROXY` env → WinHTTP (pre-onboarding) | None (direct) |
| **Extensions** | `azcmagent extension list` (12 types: SQL, AMA, MDE, WAC, KV, HRW, CT, GA, UM, CS, DA, DSQL) | `-CheckIncludeAll` tests all |
| **Regional endpoints** | `azcmagent check` output parsing | DNS probe with abbreviation map (40+ regions) |
| **Gateway URL** | `azcmagent show -j` → `.gatewayUrl` | Manual `-Mode Gateway` |
| **Agent status** | `azcmagent show -j` → `.status` / `.agentVersion` | N/A |

## PKI/OCSP/CRL Bypass Validation

When a WinHTTP proxy is detected, the script validates that all PKI endpoints are in
the proxy bypass list (WinHTTP bypass or `NO_PROXY` environment variable). This is
critical for **Azure Firewall explicit proxy** deployments, where Windows SCHANNEL
sends OCSP/CRL requests through WinHTTP — if these endpoints are not bypassed, the
firewall rejects them with *"Received a non-proxy request on a proxy port"*.

**PKI endpoints validated:**

| Endpoint | Purpose |
| -------- | ------- |
| `oneocsp.microsoft.com` | OCSP primary |
| `crl.microsoft.com` | CRL Microsoft root |
| `crl2.microsoft.com` | CRL Microsoft intermediate |
| `crl3.digicert.com` | CRL DigiCert |
| `crl4.digicert.com` | CRL DigiCert alt |
| `ocsp.digicert.com` | OCSP DigiCert |
| `ctldl.windowsupdate.com` | Certificate Trust List |
| `www.microsoft.com` | PKI AIA chain |
| `caissuers.microsoft.com` | CA Issuers (AIA) |
| `login.live.com` | Live ID cert validation |

The script normalizes both WinHTTP wildcard format (`*.domain.com`) and `NO_PROXY`
format (`.domain.com`) for accurate bypass matching.

## TLS Validation

Azure Arc requires **TLS 1.2 or 1.3**. The script performs a multi-layer check:

1. **SCHANNEL registry** — verifies TLS 1.2 Client is not disabled via
   `DisabledByDefault` or `Enabled=0`.
2. **Live handshake** — attempts a real TLS 1.2 connection to
   `login.microsoftonline.com` (through proxy if configured).
3. **Cipher suites** — verifies required GCM ciphers are present:
   - TLS 1.2: `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`,
     `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`
   - TLS 1.3: `TLS_AES_256_GCM_SHA384`, `TLS_AES_128_GCM_SHA256`
4. **.NET StrongCrypto** — checks `SchUseStrongCrypto` registry (recommended for
   PS 5.1).
5. **Server 2012 (non-R2)** — warns that SQL Arc (`*.arcdataservices.com`) is not
   supported.

## References

- [Azure Arc network requirements (consolidated)](https://learn.microsoft.com/azure/azure-arc/network-requirements-consolidated)
- [Azure Arc Gateway](https://learn.microsoft.com/azure/azure-arc/servers/arc-gateway)
- [Azure Firewall explicit proxy with Arc](https://learn.microsoft.com/azure/azure-arc/azure-firewall-explicit-proxy)
- [Troubleshoot Windows TLS configuration](https://learn.microsoft.com/azure/azure-arc/servers/troubleshoot-networking#windows-tls-configuration-issues)
- [Private Link for Azure Arc](https://learn.microsoft.com/azure/azure-arc/servers/private-link-security)
