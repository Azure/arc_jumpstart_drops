---
type: docs
title: "Azure Arc Connectivity Check"
linkTitle: "Azure Arc Connectivity Check"
weight: 1
description: >
    Validate Azure Connected Machine agent connectivity and endpoints for public or Private Link deployments, with automatic mode detection and proxy awareness.
---

## Overview

`ArcEndpointCheck.ps1` validates network connectivity between a Windows machine and the Azure endpoints required by the Azure Connected Machine agent (Azure Arc). It performs DNS resolution, TCP reachability, and HTTPS probe checks for both **public** and **Private Link** deployments, automatically detecting the deployment mode and honoring the agent's proxy configuration.

Use it before or after onboarding a server to Azure Arc to quickly confirm that every required endpoint is reachable and to pinpoint DNS, firewall, or proxy issues.

## Prerequisites

- Windows Server 2012 R2 or later (Windows PowerShell 5.1 or PowerShell 7+).
- Run the script from the machine you are validating (locally).
- Outbound access to the Azure Arc endpoints (directly, or through a proxy / Private Link).
- Optional: the Azure Connected Machine agent (`azcmagent`) installed, so the script can read the configured proxy URL, bypass list, and run `azcmagent check`.

## Getting started

Download `ArcEndpointCheck.ps1` and run it from an elevated PowerShell session on the target machine.

| Parameter | Description | Default |
| --- | --- | --- |
| `-Region` | Azure region used to build region-specific endpoints. | `eastus2` |
| `-Mode` | Deployment mode to validate: `Auto`, `Public`, or `Private`. `Auto` detects Private Link from DNS. | `Auto` |
| `-ProxyUrl` | Explicit proxy URL. Overrides the agent's `proxy.url` and `HTTPS_PROXY`. | (auto-detected) |
| `-LogFilePath` | Path of the transcript/log file. | `C:\temp\Arclogfile.txt` |
| `-IncludeSQL` | Also validate Azure Arc-enabled SQL Server endpoints. | off |
| `-IncludeAMA` | Also validate Azure Monitor Agent endpoints. | off |
| `-IncludeMDE` | Also validate Microsoft Defender for Endpoint endpoints. | off |
| `-IncludeWAC` | Also validate Windows Admin Center in Azure endpoints. | off |
| `-CheckIncludeAll` | Validate every optional endpoint group and run the broadest `azcmagent check`. | off |

## Using the script

Run a full automatic check (detects Public vs Private Link):

```powershell
.\ArcEndpointCheck.ps1
```

Validate a specific region and force Private Link mode:

```powershell
.\ArcEndpointCheck.ps1 -Region westeurope -Mode Private
```

Include the Azure Arc-enabled SQL Server endpoints:

```powershell
.\ArcEndpointCheck.ps1 -IncludeSQL
```

Validate through an explicit proxy and check every optional endpoint group:

```powershell
.\ArcEndpointCheck.ps1 -ProxyUrl "http://10.0.1.4:8443" -CheckIncludeAll
```

The script writes a color-coded summary to the console and a transcript to the log file. It exits with code `0` when all required checks pass and `1` when any check fails, so it can be used in automation and onboarding pipelines.
