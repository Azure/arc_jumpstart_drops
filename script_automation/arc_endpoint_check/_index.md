---
type: docs
title: "Azure Arc Connectivity Check"
linkTitle: "Azure Arc Connectivity Check"
weight: 1
description: >
    Validate Azure Connected Machine agent connectivity and endpoints for public
    or Private Link deployments, with automatic mode detection and proxy awareness.
---

## Overview

This script helps identify connectivity issues with the Azure Connected Machine agent
and its required endpoints. It validates the endpoint list from the official Azure Arc
network requirements, performs **DNS resolution**, **TCP/443** reachability, and **HTTP**
probes, runs `azcmagent check`, and logs everything for review.

Compared to earlier versions, it is fully **parameter-driven** (no manual editing of the
script is required) and adds:

- **Automatic Public vs Private Link detection** (`azcmagent show` + DNS heuristic), with a
  manual override (`-Mode`).
- **Proxy awareness** that mirrors the Connected Machine agent precedence
  (`azcmagent proxy.url` > `HTTPS_PROXY`) and honors `proxy.bypass` categories
  (AAD, ARM, Arc, AMA, ArcData). The Windows system-wide proxy (WinHTTP/WinINET) is
  reported but never applied automatically, matching the agent's behavior.
- **Optional extension endpoint groups**: SQL Server enabled by Azure Arc, Azure Monitor
  Agent (AMA), Microsoft Defender for Endpoint (MDE), and Windows Admin Center (WAC).
- **Dynamic endpoint allowlist**: in Public mode the script also queries the
  `guestnotificationservice` allowlist for the region and validates those endpoints
  (primary namespaces only). Failures here are treated as warnings and never affect the
  exit code, since this list is auxiliary.
- **IPv4-first DNS resolution** (Private Link uses A records), avoiding false "public"
  classification when public AAAA records coexist.
- A machine-readable **exit code** (`0` = all checks OK, `1` = at least one failure).

## Prerequisites

- **Windows PowerShell 5.1 or later** (Windows only — the script uses `netsh`,
  `Resolve-DnsName`, and `azcmagent.exe`).
- Outbound network connectivity to the Azure Arc endpoints (directly or via proxy).
- *(Optional)* The **Azure Connected Machine agent** (`azcmagent.exe`). It is only needed
  for the final `azcmagent check`; DNS/TCP/HTTP tests run without it.
- Run from an **elevated PowerShell** session for the most complete results.

## Getting Started

Download [ArcEndpointCheck.ps1](./ArcEndpointCheck.ps1) and run it on the server where the
Azure Arc agent is (or will be) installed.

Unlike previous versions, **you no longer edit the script**. Everything is controlled by
parameters:

| Parameter          | Description                                                                                          | Default                  |
| ------------------ | ---------------------------------------------------------------------------------------------------- | ------------------------ |
| `-Region`          | Azure region (e.g., `eastus2`, `brazilsouth`).                                                        | `eastus2`                |
| `-Mode`            | `Auto`, `Public`, or `Private`. `Private` automatically adds `--enable-pls-check` to `azcmagent check`. | `Auto`                   |
| `-ProxyUrl`        | Explicit HTTP/HTTPS proxy (e.g., `http://10.0.1.4:8443`). If omitted, auto-detects `azcmagent proxy.url` then `HTTPS_PROXY`. | *(auto-detect)*          |
| `-LogFilePath`     | Path to the log file.                                                                                | `C:\temp\Arclogfile.txt` |
| `-IncludeSQL`      | Adds Azure Arc-enabled SQL Server endpoints (`*.arcdataservices.com`, plus `graph.microsoft.com` for Microsoft Entra auth). | *(off)*                  |
| `-IncludeAMA`      | Adds Azure Monitor Agent endpoints.                                                                  | *(off)*                  |
| `-IncludeMDE`      | Adds Microsoft Defender for Endpoint endpoints.                                                      | *(off)*                  |
| `-IncludeWAC`      | Adds Windows Admin Center endpoints.                                                                 | *(off)*                  |
| `-CheckIncludeAll` | Runs `azcmagent check` with `--extensions all --include-all` (all extensions + extended use cases such as Windows Server pay-as-you-go). | *(off)*                  |

> The public/private choice is handled automatically. In `Private` mode the script adds
> `--enable-pls-check` for you — there is no longer any parameter to remove manually.

## Using the Script

Run the script on the target server, keeping in mind environmental factors such as
firewall rules, proxy configuration, region, and whether the connection is public or
private. Examples:

```powershell
# Auto-detect Public/Private, default region (eastus2)
.\ArcEndpointCheck.ps1

# Specific region + SQL and AMA endpoints
.\ArcEndpointCheck.ps1 -Region brazilsouth -IncludeSQL -IncludeAMA

# Force an explicit proxy for all HTTP tests
.\ArcEndpointCheck.ps1 -Region eastus2 -ProxyUrl http://10.0.1.4:8443

# Force Public mode (useful before the agent is installed)
.\ArcEndpointCheck.ps1 -Mode Public

# Force Private Link validation (adds --enable-pls-check) with a custom log path
.\ArcEndpointCheck.ps1 -Mode Private -LogFilePath D:\logs\arc-pls.txt

# Full pre-onboarding validation of all extension endpoints
.\ArcEndpointCheck.ps1 -Mode Private -CheckIncludeAll -Verbose -IncludeSQL -IncludeAMA -IncludeMDE -IncludeWAC
```
