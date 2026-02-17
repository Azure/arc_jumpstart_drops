---
title: Arc Remote Run Command (Cross-Platform)
description: Remotely run OS-specific scripts across Arc-enabled Windows and Linux servers using Run Command. No SSH or WinRM are required.
author: Matthew Dowst
ms.date: 2025-01-21
---

## Overview

This Azure Arc Jumpstart Drop provides a cross-platform PowerShell automation for running remote commands against **Azure Arc-enabled servers** (Windows and Linux) using the **Run Command** feature built into the Connected Machine agent.

With this Drop, you can:

- Target both **Windows and Linux** in a single execution
- Supply different scripts per OS (PowerShell for Windows, shell for Linux)
- Select Arc-enabled machines by name, tag, or resource group
- Optionally wait for execution to retrieve exit code, stdout, and stderr
- Run automation without SSH, WinRM, or inbound firewall rules

Run Command enables Day-2 operations across hybrid and multi-cloud fleets without requiring direct connectivity or reconfiguration of network security boundaries.

---

## Prerequisites

To use this Drop, you will need:

- An Azure subscription and Resource Group
- Azure Arc-enabled servers with the **Connected Machine Agent** installed
- Agent version **1.33 or later**
- PowerShell 7.x (recommended)
- Az modules:
  - `Az.Accounts`
  - `Az.ConnectedMachine` v1.1.0+

Install required modules:

```powershell
Install-Module Az.Accounts,Az.ConnectedMachine -Scope CurrentUser
````

Authenticate to Azure:

```powershell
Connect-AzAccount
Select-AzSubscription -SubscriptionId '<subscription-id>'
```

---

## Getting Started

Clone or download this Drop's content from the Jumpstart Drops repository and navigate into the folder:

```bash
git clone https://github.com/Azure/arc_jumpstart_drops
cd AzureArc_Jumpstart_Drops/arc-remote-run-command
```

Load the main function script:

```powershell
. ./Invoke-ArcRemoteRunCommand.ps1
```

For addtional help and a complete list of parameters refer to the README.md.

### Run the included demo

The quickest way to get started is to run the demo script:

```powershell
.\example\demo.ps1 -SubscriptionId '<subscription-id>' -ResourceGroupName '<resource-group>'
```

The demo will:
- Connect to your Azure subscription
- Discover Arc-enabled servers in the specified resource group
- Execute a basic health check (hostname, user, and date/time) across all servers
- Display results from Windows and Linux machines side-by-side

### Run a basic health check manually

You can also invoke the function directly for more control:

```powershell
$win = 'hostname; whoami; Get-Date'
$lin = 'hostname; whoami; date'

Invoke-ArcRemoteRunCommand -ResourceGroupName '<resource-group>' -WindowsScript $win -LinuxScript $lin
```

This will return execution results for all Arc-enabled servers in the specified resource group.

---

## Example Scenarios

### Cross-Platform App Restart

Targets all Arc-enabled servers in a resource group.\
Restarts service on both Windows and Linux.

```powershell
$win = 'Restart-Service MyApp'
$lin = 'sudo systemctl restart myapp'

Invoke-ArcRemoteRunCommand -ResourceGroupName '<resource-group>' -WindowsScript $win -LinuxScript $lin
```

---

### Target by Tags (Role + Environment)

Targets Arc-enabled servers in a resource group with tags `env=prod` and `role=web`.\
Restarts IIS on Windows and nginx/httpd on Linux.\
Run Commands are submitted as jobs and polled until completion or timeout.\
`TagFilter` is a Hashtable of tag key/value pairs to filter machines. All supplied key/value pairs must match (logical AND).

```powershell
$InvokeArcRemoteRunCommandParam = @{
	ResourceGroupName = '<resource-group>'
	TagFilter         = @{ env = 'prod' ; role = 'web' }
	WindowsScript     = 'Restart-Service W3SVC -Force'
	LinuxScript       = 'sudo systemctl restart nginx'
	Wait              = $true
	WaitSeconds       = 600
}
Invoke-ArcRemoteRunCommand @InvokeArcRemoteRunCommandParam
```

---

### Remote Reboot (Windows Only)

Runs a restart operation on specific machines arc-win-01 and arc-lnx-01.\
Windows receives a reboot command.\
By leaving off the `-LinuxScript` any Linux devices will be skipped even if they are listed in the `-MachineName` parameter.

```powershell
$win = 'Restart-Computer -Force'

Invoke-ArcRemoteRunCommand -ResourceGroupName '<resource-group>' -MachineName 'arc-win-01','arc-lnx-01' -WindowsScript $win
```

---

### File-Based Script Input

Get content from a local script and pass it to the remote machines.

```powershell
$win = Get-Content restart.ps1 -Raw
$lin = Get-Content restart.sh  -Raw

Invoke-ArcRemoteRunCommand -ResourceGroupName '<resource-group>' -WindowsScript $win -LinuxScript $lin
```


---

## Scenarios & Use Cases

This Drop is useful for:

* Health checks and diagnostics
* Restarting applications and services
* Executing remediation scripts
* Cross-platform configuration enforcement
* Gathering logs and inventory data
* Running controlled change operations
* Hybrid/cloud/edge fleet management

---

## Security & Access

This Drop does **not** require SSH, WinRM, or inbound ports.

Access is governed entirely through **Azure RBAC**, particularly:

* `Connected Machine Resource Administrator`
* `Reader` (optional for discovery)
* Custom RBAC roles can be applied where needed

---

## Feedback & Support

To report issues, request enhancements, or contribute improvements, please open an issue or PR via the GitHub repository.

