---
type: docs
title: "Azure Arc SQL LeastPrivilege Activation"
linkTitle: "Azure Arc SQL LeastPrivilege Activation"
weight: 1
description: >
  Runbook to enable the LeastPrivilege FeatureFlag on Azure Arc SQL-enabled machines using Resource Graph and Azure CLI.
---

## Overview

This repository contains a PowerShell Runbook that automates the activation of the **LeastPrivilege FeatureFlag** on Azure Arc SQL-enabled machines. It uses Azure Resource Graph to identify machines where the flag is missing or disabled and applies the change using Azure CLI.

This improves security posture and ensures consistent configuration across hybrid environments.

> **Note**  
> This document and script were created based on the official Microsoft guidance:  
> [Configure least privilege for Azure Arc–enabled SQL Server](https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/configure-least-privilege?view=sql-server-ver17).

## Getting Started

The script is designed to run in an **Azure Automation Account** with **Managed Identity** enabled. It queries all subscriptions accessible to the identity, identifies eligible machines, and enables the LeastPrivilege flag.

### Why Use This Script?

By default, some Azure Arc SQL machines may not have the LeastPrivilege FeatureFlag enabled, which can lead to elevated permissions and inconsistent configurations. This script ensures the flag is applied consistently across all connected machines.

## Deploying Artifacts

The script **`RunBook-ArcSQLEnableLeastPrivilege.ps1`** is part of this repository and can be imported into an Azure Automation Runbook.

You can access it directly at the following link:  
[RunBook-ArcSQLEnableLeastPrivilege.ps1](./RunBook-ArcSQLEnableLeastPrivilege.ps1)

## Prerequisites

### Automation Account

- PowerShell Runtime version **7.2 or higher**
- Modules:
  - `Az.Accounts` version **2.7.5 or higher**
  - `Az.ResourceGraph`
- **Azure CLI** must be available in the environment
- **Managed Identity** must be enabled and assigned permissions to:
  - Read and modify Azure Arc machines
  - Query Resource Graph

### Permissions

The Managed Identity must have the following roles assigned:
- **Reader** or **Contributor** on target subscriptions
- **Hybrid Compute Administrator** (or equivalent) to modify Azure Arc machine extensions

## What the Script Does

- Authenticates using Managed Identity (PowerShell and Azure CLI)
- Validates environment and required modules
- Ensures the `arcdata` CLI extension is installed
- Queries Azure Resource Graph for SQL-enabled Azure Arc machines
- Identifies machines missing or with disabled LeastPrivilege FeatureFlag
- Enables the flag using Azure CLI
- Logs results in structured format (CSV-style)

## Example Execution Output

Below is a sample output from the Runbook execution. It demonstrates the structured logging format and the result of enabling the LeastPrivilege FeatureFlag on Azure Arc SQL-enabled machines:

```powershell
[2025-09-18 22:36:56][INFO] Environment successfully validated.
[2025-09-18 22:36:56][INFO] Authenticating to Azure using managed identity (PowerShell)...
[2025-09-18 22:36:58][INFO] Authenticating to Azure CLI using managed identity...
[2025-09-18 22:37:13][INFO] Authentication completed successfully.
[2025-09-18 22:37:14][INFO] Installing 'arcdata' extension...
[2025-09-18 22:37:48][INFO] 'arcdata' extension installed successfully.
[2025-09-18 22:37:48][INFO] Setting context for subscription: ME-MngEnvMCAP385546-farodrig-1 (c0d36e7b-027e-4956-94bf-6e17dbf5e791)
[2025-09-18 22:37:48][INFO] Querying machines in subscription c0d36e7b-027e-4956-94bf-6e17dbf5e791...
[2025-09-18 22:37:49][INFO] Processing machine: app01 in resource group rg-azurearc-itpro-br...
[2025-09-18 22:37:58][RESULT] "app01","rg-azurearc-itpro-br","c0d36e7b-027e-4956-94bf-6e17dbf5e791","leastprivilege","false","true","connected","9/18/2025 8:48:31 PM","Success"
[2025-09-18 22:37:58][INFO] Setting context for subscription: ME-MngEnvMCAP385546-farodrig-2 (8e467ebb-7651-4c72-86ec-32f0e7359355)
[2025-09-18 22:37:58][INFO] Querying machines in subscription 8e467ebb-7651-4c72-86ec-32f0e7359355...
[2025-09-18 22:37:59][INFO] No machines with disabled/missing FeatureFlags and 'connected' status found in subscription 8e467ebb-7651-4c72-86ec-32f0e7359355.
[2025-09-18 22:37:59][INFO] Execution completed successfully.
```
