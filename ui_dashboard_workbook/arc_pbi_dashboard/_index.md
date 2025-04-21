---
type: docs
title: "Azure Arc PowerBI Dashboard"
linkTitle: "Azure Arc PowerBI Dashboard"
weight: 1
description: >
---

## Azure Arc PowerBI Dashboard

This is a sample PowerBI dashboard used to demonstrate the insights available via Arc and Azure Resource Graph for your IT infrastructure. The dashboard covers a wide range of components including servers, SQL Instances on Virtual Machines, SQL Databases on Virtual Machines and Extended Security Update forecasting for servers connected to Arc or in Azure. The Dashboard uses the PowerBI connector for Azure Resource Graph to connect to your Azure Subscription(s). 

The Dashboard contains:

* **Server Inventory** - A detailed inventory of all servers, both Azure and Azure Arc-connected, providing a clear overview of server landscape
* **SQL Inventory** - Information on SQL instances, including both Azure SQL and Azure Arc-enabled SQL servers, ensuring you have a complete view of your SQL VM environment
* **Databases** - Insights into databases managed through Azure Arc, helping you track and manage your database assets effectively.
* **ESU Forecast** - An estimate of future costs for Extended Security Updates (ESUs) for Windows Server 2016 and SQL Server 2016, based on current pricing. For detailed prices of ESUs see: [Azure Arc pricing](https://azure.microsoft.com/en-us/pricing/details/azure-arc/core-control-plane/)

## Screenshots

Here are some screenshots of the Arc Dashboard:
<p float="left">
  <img src="artifacts/media/server_inventory_screenshot.png" alt="Server Inventory" width="45%" />
  <img src="artifacts/media/sqlserver_inventory_screenshot.png" alt="SQL Server Inventory" width="45%" />
</p>
<p float="left">
  <img src="artifacts/media/sqldatabase_inventory_screenshot.png" alt="SQL Database Inventory" width="45%" />
  <img src="artifacts/media/esu_forecast_screenshot.png" alt="ESU Forecast" width="45%" />
</p>

## Contributors

This Jumpstart Drop was originally written by the following contributors:

* [Mark Jones | Principal Cloud Solution Architect at Microsoft](www.linkedin.com/in/joneslmark)

## Prerequisites

* Azure Subscription(s)
* Azure Arc-enabled servers within your Azure subscription(s)
* If you have SQL server VMs that are Arc-enabled, these will require the SQL Server Extension to be enabled
* Azure Credential with read access to Azure Resource Graph, to the Azure Subscription. To learn more about this see: [Permissions in Azure Resource Graph](https://learn.microsoft.com/en-us/azure/governance/resource-graph/overview#permissions-in-azure-resource-graph)
* Internet Connection
* PowerBI Desktop. You can download this at: [Download PowerBI Desktop](https://www.microsoft.com/en-us/power-platform/products/power-bi/downloads?msockid=0c5db1779a21637012a6a5f29bea62ee)

## Getting Started

### How to install the PowerBI report

1. Download the PowerBI Template file: <a href="/azure_arc_dashboard_v1.pbit">Jumpstart PBI Dashboard</a>
2. Open PowerBI Template File, upon first opening the Dasboard will attempt refresh
3. During the refresh, PowerBI will prompt for credentials for "Azure Resource Graph"

<img src="artifacts/media/arg_connector_screenshot.png" alt="Azure Resource Graph Connector" width="60%" />

5. Sign in with a login that has Read Access to Azure Resource Graph for the subscription(s) you want the report to view
6. Click "Connect" each time you are prompted
7. Ignore any errors (see known Issues)
8. Save your new PBI Dashboard

### Data Sources Used
The Dashboard has the following data sources:
1. Azure Resource Graph - Used to gather Servers, SQL Server VM Instances and SQL VM Databases across Azure and Connected to Azure Arc. Kusto Queries are saved to: <a href="/artifacts/arg_queries/">Azure Resource Graph Queries</a>
2. Learn.microsoft.com - Used to gather latest SQL Patch information
3. Reference CSVs - See <a href="/artifacts/reference/">Here</a> - CSVs containing Azure SKUs and Product Lifecycle dates

## Resources

For more information please review the following resources:

* [Azure Resource Graph](https://learn.microsoft.com/en-us/azure/governance/resource-graph/overview#permissions-in-azure-resource-graph)
* [Arc-Connected Servers](https://learn.microsoft.com/en-us/azure/azure-arc/servers/overview)
* [PowerBI Connector](https://learn.microsoft.com/en-us/azure/governance/resource-graph/power-bi-connector-quickstart?tabs=power-bi-desktop#connect-azure-resource-graph-with-power-bi-connector)


## Known Issues
1. If there are no Arc or Azure resources (Servers, SQL Instances, SQL Databases) in your subscription, or the SQL server extension is missing, the Report may encounter errors