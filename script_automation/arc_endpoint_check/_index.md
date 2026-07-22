---
type: docs
title: "Azure Arc Connectivity Check"
linkTitle: "Azure Arc Connectivity Check"
weight: 1
description: >
  Validate Azure Arc connectivity, proxy behavior, agent local health, DNS, TCP,
  HTTP, TLS, PKI/OCSP/CRL reachability, and platform-specific metadata paths for
  Public, Private, and Gateway scenarios.
---

## Overview

This PowerShell script validates Azure Arc connectivity with emphasis on practical
interpretation of real-world network paths, especially in environments that use:

- direct outbound access
- explicit proxy
- Private Link
- Gateway
- split-network designs

It inspects local Azure Arc agent state, tests required and optional endpoints,
checks TLS posture, reviews PKI/OCSP/CRL reachability, and classifies findings as
blocking failures or non-blocking warnings.

When the Azure Connected Machine agent is installed, the script auto-detects most
settings from the local host. When the agent is not installed, the script still works
in pre-onboarding mode for DNS/TCP/HTTP/TLS validation.

## What the script validates

| Area | Details |
| ---- | ------- |
| **Agent state** | `azcmagent show -j`, local config, service status, version, and `himds.log` tail |
| **Connectivity mode** | `Public`, `Private`, `Gateway`, or `Auto` |
| **Platform context** | `Arc`, `AzureLocal`, `AzureStackHub`, or `AzureVM` |
| **Core Arc endpoints** | Arc runtime, Guest Configuration, AAD, ARM, and lifecycle endpoints |
| **Extension endpoints** | SQL, AMA, MDE, WAC, Key Vault, Hybrid Worker, Update Manager, Guest Attestation, Dependency Agent, Defender for SQL, and others when detected |
| **DNS and TCP** | Name resolution, public/private IP classification, and TCP 443 reachability |
| **HTTP probes** | Layer-7 validation for selected endpoints, including proxy-path interpretation |
| **TLS** | SCHANNEL TLS 1.2 posture, live TLS 1.2 handshake, .NET StrongCrypto, and local cipher inventory when available |
| **PKI / OCSP / CRL** | Reachability and bypass coverage validation for revocation and certificate chain endpoints |
| **Proxy configuration** | WinHTTP, `azcmagent` proxy settings, `HTTPS_PROXY`, bypass categories, and effective proxy path |
| **Gateway behavior** | Gateway URL detection and warning when `proxy.bypass` is configured in Gateway mode |

## Key behavior in this revised version

This version was adjusted to better reflect how Azure Arc behaves in segmented
network designs and to avoid false outage conclusions.

### Important interpretation for `Private` mode

In `Private` mode, a failed path to `management.azure.com` does **not** automatically
mean Azure Arc runtime is broken.

Azure Arc Private Link Scope does **not** carry Microsoft Entra ID or Azure Resource
Manager traffic by default. Because of that, Azure Arc runtime connectivity can remain
healthy even when the ARM path is degraded on a separate proxy or control-plane route.

If Arc private-capable endpoints remain healthy and `azcmagent check` reports
`critical_failures=0`, the script treats ARM/proxy-path degradation as a
**non-blocking warning**, not a runtime outage.

Typical example:

- Arc private endpoints are reachable
- Guest Configuration endpoints are reachable
- AAD bypass works
- `management.azure.com` fails only through the configured proxy path
- `azcmagent check` reports `critical_failures=0`

In that case, the script classifies the result as a warning such as:

- `ControlPlane WARN`
- proxy-path non-blocking warning
- PKI/OCSP warning when relevant

This avoids false outage conclusions in split-network environments.

### Important note about probe interpretation

The script distinguishes between:

- general endpoint reachability
- the effective path used by the Azure Arc agent or proxy configuration

Because of that, an endpoint can appear reachable in a generic DNS/TCP probe while the
actual agent path still fails through the configured proxy. This distinction is
especially important for `management.azure.com` in `Private` mode.

### When ARM failure is actionable

A failed ARM path should be treated as operationally relevant when:

- onboarding is failing
- extension deployment or ARM-driven operations are failing
- the intended design requires ARM to traverse a private path
- the configured proxy should be carrying ARM traffic but is not reachable

If ARM must stay private, configure **Resource Management Private Link** separately.
Do not assume Azure Arc Private Link Scope alone covers that path.

## Prerequisites

- **Windows PowerShell 5.1 or later**
- outbound connectivity to the required Azure Arc endpoints
- **optional:** Azure Connected Machine agent (`azcmagent.exe`)
- recommended: run from an **elevated PowerShell** session

If `azcmagent` is not installed, the script runs in pre-onboarding mode and skips
agent-specific discovery such as `azcmagent check`, agent config, and extension
enumeration.

## Parameters

| Parameter | Description | Default |
| --------- | ----------- | ------- |
| `-Region` | Azure region. Auto-detected from `azcmagent show -j` when available. | auto-detect, otherwise `eastus2` fallback |
| `-Mode` | `Auto`, `Public`, `Private`, or `Gateway` | `Auto` |
| `-Platform` | `Auto`, `Arc`, `AzureLocal`, `AzureStackHub`, or `AzureVM` | `Auto` |
| `-ProxyUrl` | Explicit proxy override | auto-detect |
| `-LogFilePath` | Output log path | `C:\temp\ArcEndpointCheck_<HOSTNAME>.txt` |
| `-SkipPKI` | Skip PKI / OCSP / CRL validation | off |
| `-SkipExtensions` | Skip extension endpoint checks | off |
| `-CheckIncludeAll` | Include all extension endpoint groups | off |
| `-SkipAgentHealth` | Skip local agent health inspection | off |

## Getting Started

Download the script and run it on the target server.

### Post-onboarding

```powershell
# Full auto-detection
.\arc-endpoint-check-revised.ps1

# Force Private mode
.\arc-endpoint-check-revised.ps1 -Mode Private

# Force a specific region
.\arc-endpoint-check-revised.ps1 -Region eastus2

# Test all extension groups
.\arc-endpoint-check-revised.ps1 -CheckIncludeAll
