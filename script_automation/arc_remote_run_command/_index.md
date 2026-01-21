
## Overview

![cover selected]("./img/Example_144828.png")

### Drop Details
This Drop demonstrates how to use Azure Arc Run Command for Day-2 operations across mixed Windows and Linux fleets without requiring SSH, WinRM, inbound ports, or direct network access. It allows users to supply different scripts per OS, target machines via name, tag, or resource group, and optionally wait for execution results including exit codes and output. Example scenarios include service restarts, app deployments, diagnostics, inventory, and cross-platform health checks. Ideal for hybrid and multi-cloud environments where Arc provides a unified execution control plane across on-premises, edge, and public clouds.

## Prerequsities

- An Azure subscription and Resource Group 



      
- Azure Arc-enabled servers with the **Connected Machine Agent** installed 



      
- Agent version **1.33 or later** 



      
- PowerShell 7.x (recommended) 



      
- Az modules:   `Az.Accounts`  and  `Az.ConnectedMachine` v1.1.0+ 

  ```shell
  Install-Module Az.Accounts,Az.ConnectedMachine -Scope CurrentUser
  ```

      

## Getting Started
#### Getting Started
Clone or download this Drop's content from the Jumpstart Drops repository and navigate into the folder:
  ```shell
  git clone https://github.com/Azure/arc_jumpstart_drops cd AzureArc_Jumpstart_Drops/arc-remote-run-command
  ```

## Development Artifacts
#### Sub Header
Description




## Resource
#### Description

