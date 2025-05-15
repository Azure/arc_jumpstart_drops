## Overview

#### Use Azure Monitor dashboards with Grafana for Arc-enabled K3s Cluster

This Jumpstart guide provides end-to-end automation to deploy a lightweight Kubernetes (K3s) cluster, onboard it to Azure Arc, and use Azure Monitor dashboards with Grafana to monitor resources in the Azure cloud and on an edge device. The automation script installs all required dependencies, sets up configures Azure monitor extension for metrics collection, and Grafana for visualization. This setup ensures you have comprehensive observability for your Kubernetes environment, whether running in the cloud or on-premises.

> **Note:** This Jumpstart guide demonstrates how to set up and use [Grafana](https://grafana.com/) with Azure Monitor Dashboards.

> ⚠️ **Disclaimer:** Azure Monitor dashboards with Grafana is currently in public preview. For further details and updates on availability, please refer to the [Azure Monitor dashboards with Grafana Documentation](https://aka.ms/DashboardsWithGrafanaDocs).

## Architecture
![Azure Monitor dashboards with Grafana Architecture.](./artifacts/media/monitor_grafana_arch.png)

## Prerequisites
- Clone the Azure Arc Drops repository

    ```shell
    git clone https://github.com/Azure/arc_jumpstart_drops.git
    ```

- [Install or update Azure CLI to version 2.53.0 and above](https://learn.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest). Use the below command to check your current installed version.

  ```shell
  az --version
  ```

- [Generate a new SSH key pair](https://learn.microsoft.com/azure/virtual-machines/linux/create-ssh-keys-detailed) or use an existing one (Windows 10 and above now comes with a built-in ssh client). The SSH key is used to configure secure access to the Linux virtual machines that are used to run the Kubernetes clusters.

  ```shell
  ssh-keygen -t rsa -b 4096
  ```

  To retrieve the SSH public key after it's been created, depending on your environment, use one of the below methods:
  - In Linux, use the `cat ~/.ssh/id_rsa.pub` command.
  - In Windows (CMD/PowerShell), use the SSH public key file that by default, is located in the _`C:\Users\WINUSER/.ssh/id_rsa.pub`_ folder.

  SSH public key example output:

  ```shell
  ssh-rsa o1djFhyNe5NxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxaDU6LwM/BTO1c= user@pc
  ```

- Edit the [main.bicepparam](https://github.com/microsoft/azure_arc/blob/main/azure_jumpstart_arcbox/bicep/main.bicepparam) template parameters file and supply values for your environment.
  - _`sshRSAPublicKey`_ - Your SSH public key
  - _`bastion`_ - Set to _`true`_ if you want to use Azure Bastion to connect to _js-k3s_

![Screenshot showing Bicep parameters.](./artifacts/media/bicep_parameters.png)

## Getting Started

The automation performs the following steps:

- Deploy the base infrastructure and Azure Managed Prometheus (Azure Monitor Workspace).
- Install the K3s cluster and onboard it as an Azure Arc-enabled Kubernetes cluster.
- Configure Azure Monitor Metrics extension on the connected Kubernetes cluster to send data to Azure Managed Prometheus.

### Run the automation

Navigate to the [deployment folder](https://github.com/Azure/arc_jumpstart_drops/tree/main/script_automation/arc_k8s_monitor_grafana/artifacts/Bicep) and run the below command:

```shell
az login
az group create --name "<resource-group-name>"  --location "<preferred-location>"
az deployment group create -g "<resource-group-name>" -f "main.bicep" -p "main.bicepparam"
```

### Verify the deployment

- Once your deployment is complete, you can open the Azure portal and see the resources inside your resource group.

  ![Screenshot showing all deployed resources in the resource group](./artifacts/media/deployed_resources.png)

#### Dashboard templates

- Azure managed template dashboards are pre-provisioned and automatically updated dashboards for frequently used Azure resources and Azure Kubernetes Services. Browse to Azure Monitor and select _Dashboards with Grafana_.

  ![Screenshot showing Azure Monitor dashboards with Grafana](./artifacts/media/monitor_grafana.png)

- Select _Kubernetes | Compute Resources | Namespace (Workloads)_ dashboard under _Azure Managed Prometheus_ dashboard template.

  ![Screenshot showing Grafana dashboard 01](./artifacts/media/monitor_grafana_builtin_01.png)

- Select the newly created _js-amw_ Azure Monitor Workspace data source and k3s cluster name (_js-k3s-*_). The dashboard will show the CPU and memory usage for the selected namespace.

  ![Screenshot showing Grafana dashboard 02](./artifacts/media/monitor_grafana_builtin_02.png)

- As with traditional Grafana dashboards, you can filter by namespace to view specific metrics. Additionally, you can adjust the time range and refresh interval to customize the metrics displayed.

  ![Screenshot showing Grafana dashboard 03](./artifacts/media/monitor_grafana_builtin_03.png)

#### Import Grafana dashboards

- In addition to dashboard templates, you can import Grafana dashboards. Browse to Azure Monitor and select _Dashboards with Grafana_. Click on _New_ and select _Import_.

  ![Screenshot showing Grafana dashboard import 01](./artifacts/media/monitor_grafana_import_01.png)

- Browse to the [Grafana dashboard gallery](https://grafana.com/grafana/dashboards/). Select a dashboard you want to import using a JSON file or Dashboard ID. Input the Dashboard ID. For example, you can use the _Node Exporter Full_ dashboard with ID _1860_. Click on _Load_.

  ![Screenshot showing Grafana dashboard import 02](./artifacts/media/monitor_grafana_import_02.png)

- Provide the import details for dashboard title, subscription, resource group, location and prometheus data source (_js-amw_). Click on _Import_.

  ![Screenshot showing Grafana dashboard import 03](./artifacts/media/monitor_grafana_import_03.png)

- Review the imported dashboard and make any necessary filter adjustments to select the data source (_js-amw_).

  ![Screenshot showing Grafana dashboard import 04](./artifacts/media/monitor_grafana_import_04.png)


### Resources

- See [Use Azure Monitor dashboards with Grafana](https://aka.ms/DashboardsWithGrafanaDocs) for the full instructions to set this up yourself.
- Enable monitoring for Azure Arc-enabled Kubernetes clusters using [Managed Prometheus](https://learn.microsoft.com/azure/azure-monitor/containers/kubernetes-monitoring-enable?tabs=cli#arc-enabled-cluster).
- Enable monitoring for Azure Kubernetes clusters using [Managed Prometheus](https://learn.microsoft.com/azure/azure-monitor/containers/kubernetes-monitoring-enable?tabs=cli#aks-cluster).