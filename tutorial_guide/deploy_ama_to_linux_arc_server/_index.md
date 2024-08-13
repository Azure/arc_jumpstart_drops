## Overview

This Drop will you guide you through using the Azure Monitor Agent on an existing Linux Arc-enabled server.

## Prerequisites

- This Drop starts at the point where you have already deployed and connected one or more machines to Azure Arc.  If you need an Azure Arc-enabled server, search for other Drops or use a Jumpstart scenario like [Deploy a local Ubuntu server hosted with Vagrant and connect it Azure Arc](https://azurearcjumpstart.io/azure_arc_jumpstart/azure_arc_servers/vagrant/local_vagrant_ubuntu/).  The official documentation for connecting a machine to Azure Arc is available [here](https://learn.microsoft.com/en-us/azure/azure-arc/servers/learn/quick-enable-hybrid-vm).

- [Install or update Azure CLI to the latest version](https://learn.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest).

- An existing resource group in Azure.


## Getting Started

### Deployment

Set the name of your resource group, Arc-enabled server, and the name of the to-be created Log Analytics Workspace:

| Variable Name      | Description                        |
|--------------------|------------------------------------|
| `RESOURCE_GROUP`   | Your existing resource group name           |
| `ARC_MACHINE_NAME` | Your existing connected machine name        |
| `WORKSPACE_NAME`   | Your desired to-be created Log Analytics Workspace 

For example,
```bash
RESOURCE_GROUP=drop-monitoring-rg
ARC_MACHINE_NAME=drop-machine-linux
WORKSPACE_NAME=drop-law
```

Using an Azure Resource Manager (ARM) template, you'll deploy the following resources:
- A Log Analytics Workspace
- A data collection rule
- A data collection rule association
- The Azure Monitor Agent extension for your existing Arc-enabled server

To deploy, run:

```
az deployment group create -g $RESOURCE_GROUP --name drop-monitoring-deployment --template-file ama-linux-template.json --parameters workspaceName=$WORKSPACE_NAME --parameters vmName=$ARC_MACHINE_NAME
```

After the deployment completes, verify that the data collection rule and Log Analytics Workspace were created.

![Screenshot of the Azure Portal showing the created resources](./media/01-portal-resources.png)

Next, verify that the Azure Monitor Agent is installed as an Extension.  Note that it may show its status as "Creating" initially while the extension is deployed.

![Screenshot of the Azure Portal showing the AMA extension](./media/02-ama-extension.png)

### Viewing Metrics and Logs

It will take several minutes for the AzureMonitorLinuxAgent extension to be installed (if not already installed previously), followed by another few minutes for performance metrics and syslog data to begin to be populated.  Afterwards, naviate to the Logs section of your Arc-enabled server.

Run the following Kusto Query Language (KQL) query to see the types of data being collected:

```
Perf
| summarize by ObjectName, CounterName
```

![Screeshot of KQL query showing countername and objectname](./media/03-kql-counters.png)

This should match the performance counters that are specified in the ARM template.

Now let's chart a specific metric, percent processor time, by running:

```
Perf
| where CounterName == "% Processor Time"
| where ObjectName == "Processor"
| summarize avg(CounterValue) by bin(TimeGenerated, 15min), Computer, _ResourceId // bin is used to set the time grain to 15 minutes
| render timechart
```

![Screenshot of KQL query showing percent processor time](./media/04-kql-processor-time.png)

In addition to these performance counters, the data collection rule also collects from Syslog.  Run the following query to see the last 100 Syslog records:

```
// All Syslog 
// Last 100 Syslog. 
Syslog 
| top 100 by TimeGenerated desc
```

![Screenshot of KQL query showing Syslog records](./media/05-kql-syslog.png)

The actual content of these queries will differ based on the activity occuring on your Arc-enabled server.  From here, you can run additional KQL queries or create alert rules based on the data being collected.

## Resources

For more information on KQL, such as to build your own queries, refer to [Get started with log queries in Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/get-started-queries).

To learn more about data collection rules, refer to [Data Collection rules in Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-overview).

Finally, to learn more about the Azure Monitor Agent, refer to [Azure Monitor Agent overview](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-overview)