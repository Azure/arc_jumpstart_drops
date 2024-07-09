---
type: docs
title: "Azure Arc Windows ESU Dashboard"
linkTitle: "Azure Arc Windows ESU Dashboard"
weight: 1
description: >
---

## Azure Arc Windows ESU Dashboard

This dashboard has been created to enable you to view several elements of the Windows or Linux servers you have deployed the Azure Arc agent to in one simple view.   Within this dashboard you will be able to see: 
* The Windows/Linux servers that have the Arc agent installed
* A count of what operating systems are being used by these Arc enabled servers
* A view of what Arc agent version is installed
* A count of any SQL instances that have been detected on the servers with Arc agents installed
* Current Windows ESU assignment status
* An overview of whether the Azure Arc is allowed to enable [extensions](https://learn.microsoft.com/azure/azure-arc/servers/manage-vm-extensions) or not.  And the status of some of the extensions if they are allowed to be used. 

## Contributors

This Jumpstart Drop was originally written by the following contributors:

- [Sarah Lean | Senior Technical Specialist at Microsoft](www.linkedin.com/in/lauranicolasd)

## Prerequisites

- Clone the Azure Arc Drops repository

    ```shell
    git clone https://github.com/Azure/arc_jumpstart_drops.git
    ```

## Getting Started

### Import the Azure Monitor Workbook

To import the workbook navigate to the [workbook directory](https://github.com/Azure/arc_jumpstart_drops/workbooks/arc_windows_esu)and run these Azure CLI commands:

```bash
# Variables
resourcegroup=<Provide your resource group name>
location=<Provide your location>

# Create a new dashboard that is empty
az portal dashboard create --location $location --name "AzureArcESUDashboard" --resource-group $resourcegroup --input-path ".\basic_dashboard.json"

#Populate the dashboard with the configuration
az portal dashboard import --name "AzureArcESUDashboard" --resource-group $resourcegroup --input-path ".\azure_windows_esu_dashboard.json"
```

## Resources

For more information please review the following resources:

- [Azure Resource Group](https://learn.microsoft.com/azure/governance/resource-graph/overview)
- [Azure Dashboard Structure](https://learn.microsoft.com/azure/azure-portal/azure-portal-dashboards-structure)
- [Azure CLI](https://learn.microsoft.com/cli/azure/what-is-azure-cli)