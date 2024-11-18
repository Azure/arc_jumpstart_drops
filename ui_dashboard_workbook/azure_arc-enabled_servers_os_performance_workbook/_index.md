---
type: docs
title: "Azure Arc-enabled servers OS Performance Workbook"
linkTitle: "Azure Arc-enabled servers OS Performance Workbook"
weight: 2
description: >
---

## Azure Arc-enabled servers OS Performance Workbook

This Jumpstart Drop provides an Azure Monitor workbook that's intended to provide a single pane of glass for monitoring Arc-enabled servers Operating System (OS) Performance. The Azure Monitor workbook acts as a flexible canvas for data analysis and visualization in the Azure portal, gathering information from several data sources and combining them into an integrated interactive experience.

## Contributors

This Jumpstart Drop was originally written by the following contributors:

- [Alejandro Sánchez | Cloud Solution Architect at Microsoft](www.linkedin.com/in/asgsanchezgomez)

## Prerequisites

- Clone the Azure Arc Drops repository

    ```shell
    git clone https://github.com/Azure/arc_jumpstart_drops.git
    ```

- Log Analytics workspace with [VM Insights](https://learn.microsoft.com/azure/azure-arc/servers/learn/tutorial-enable-vm-insights#enable-vm-insights) data collected.

    > **Note:** This workbook will work for any server (Arc-enabled or not) sending VM Insights data to a Log Analytics workspace.

## Getting Started

### Import the Azure Monitor Workbook

To import the workbook navigate to the [workbook directory](https://github.com/Azure/arc_jumpstart_drops/workbooks/arc_os_performance/) and run these PowerShell commands:

```powershell
$OSPerformanceWorkbookParameters = "OSPerformanceWorkbook.parameters.json"
$workspaceResourceId = "<Provide your Log Analytics workspace resource ID>"
$resourceGroup = "<Provide your resource group name>"
((Get-Content -Path $OSPerformanceWorkbookParameters) -replace 'workspaceResourceId-stage',$workspaceResourceId) | Set-Content -Path $OSPerformanceWorkbookParameters

Write-Host "Deploying Azure Monitor Workbook ARM template."
Write-Host "`n"
az deployment group create --resource-group $resourceGroup --template-file "OSPerformanceWorkbook.json" --parameters "OSPerformanceWorkbook.parameters.json"
Write-Host "`n"
```

## Resources

For more information about Azure Monitor workbooks and monitoring, review the following resources:

- [Azure Monitor workbooks](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-overview)
- Azure Arc-enabled server's workbook [video](https://www.youtube.com/@azurearcjumpstart/search?query=workbook)
- [ArcBox Azure Monitor Workbook documentation](https://azurearcjumpstart.com/azure_jumpstart_arcbox/workbook/flavors/Full).