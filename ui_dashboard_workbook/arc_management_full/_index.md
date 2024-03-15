---
type: docs
title: "Azure Arc Management Workbook"
linkTitle: "Azure Arc Management Workbook"
weight: 1
description: >
---

## Azure Arc Management Workbook

This Jumpstart Drop provides an Azure Monitor workbook that is intended to provide a single pane of glass for monitoring and reporting on Arc resources. Using Azure's management and operations tools in hybrid, multi-cloud and edge deployments provides the consistency needed to manage each environment through a common set of governance and operations management practices. The Azure Monitor workbook acts as a flexible canvas for data analysis and visualization in the Azure portal, gathering information from several data sources and combining them into an integrated interactive experience.

## Contributors

This Jumpstart Drop was originally written by the following contributors:

- [Laura Nicolás | Cloud Solution Architect at Microsoft](www.linkedin.com/in/lauranicolasd)

## Prerequisites

- Clone the Azure Arc Drops repository

    ```shell
    git clone https://github.com/Azure/arc_jumpstart_drops.git
    ```

## Getting Started

### Import the Azure Monitor Workbook

To import the workbook navigate to the [workbook directory](https://github.com/Azure/arc_jumpstart_drops/workbooks/arc_management_full/)and run these PowerShell commands:

```powershell
# Configure mgmtMonitorWorkbook.parameters.json template with workspace resource id
$monitorWorkbookParameters = "mgmtMonitorWorkbook.parameters.json"
$workspaceResourceId = "<Provide your Log Analytics workspace ID>"
$resourceGroup = "<Provide your resource group name>"
(Get-Content -Path $monitorWorkbookParameters) -replace 'workbookResourceId-stage',$workspaceResourceId | Set-Content -Path $monitorWorkbookParameters

Write-Host "Deploying Azure Monitor Workbook ARM template."
Write-Host "`n"
az deployment group create --resource-group $resourceGroup --template-file "mgmtMonitorWorkbook.json" --parameters "mgmtMonitorWorkbook.parameters.json"
Write-Host "`n"
```

## Resources

For more information about ESU licenses, review the following resources:

- [Azure Monitor workbooks](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-overview)
- Azure Arc-enabled server's workbook [video](https://www.youtube.com/@azurearcjumpstart/search?query=workbook)
- [ArcBox Azure Monitor Workbook documentation](https://azurearcjumpstart.com/azure_jumpstart_arcbox/workbook/flavors/Full).
