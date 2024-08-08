## Overview

The following Jumpstart Drop will guide you on how to connect an existing Kubernetes cluster to Azure Arc using a simple shell script.

## Prerequisites

* Make sure your *kubeconfig* file is configured properly and you are working against your [k8s cluster context](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/).

* (Optional) To simplify work against multiple k8s contexts, consider using [kubectx](https://github.com/ahmetb/kubectx).

* [Install or update the latest Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest). Use the below command to check your current installed version.

* Have an identiy (either a user or service principal) that can log in to the Azure CLI and, at a minimum, has the [Kubernetes Cluster - Azure Arc Onboarding](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/containers#kubernetes-cluster---azure-arc-onboarding) role. 

* If using the Kubernetes Cluster - Azure Arc Onboarding role with a service principal, you must already have a resource group in which to onboard the cluster.

* [Enable subscription with](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types#register-resource-provider) the three resource providers for Azure Arc-enabled Kubernetes. Registration is an asynchronous process, and registration may take approximately 10 minutes.

  ```shell
  az provider register --namespace Microsoft.Kubernetes
  az provider register --namespace Microsoft.KubernetesConfiguration
  az provider register --namespace Microsoft.ExtendedLocation
  ```

  You can monitor the registration process with the following commands:

  ```shell
  az provider show -n Microsoft.Kubernetes -o table
  az provider show -n Microsoft.KubernetesConfiguration -o table
  az provider show -n Microsoft.ExtendedLocation -o table
  ```
* Create Azure service principal (SP)

    To be able to complete the scenario and its related automation, Azure service principal assigned with the “Contributor” role is required. To create it, login to your Azure account run the below command (this can also be done in [Azure Cloud Shell](https://shell.azure.com/).

    ```shell
    az login
    subscriptionId=$(az account show --query id --output tsv)
    az ad sp create-for-rbac -n "<Unique SP Name>" --role "Contributor" --scopes /subscriptions/$subscriptionId
    ```

    For example:

    ```shell
    az login
    subscriptionId=$(az account show --query id --output tsv)
    az ad sp create-for-rbac -n "JumpstartArcK8s" --role "Contributor" --scopes /subscriptions/$subscriptionId
    ```

    Output should look like this:

    ```json
    {
    "appId": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "displayName": "JumpstartArcK8s",
    "password": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "tenant": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    }
    ```

    > **Note:** If you create multiple subsequent role assignments on the same service principal, your client secret (password) will be destroyed and recreated each time. Therefore, make sure you grab the correct password.

    > **Note:** The Jumpstart scenarios are designed with as much ease of use in-mind and adhering to security-related best practices whenever possible. It is optional but highly recommended to scope the service principal to a specific [Azure subscription and resource group](https://learn.microsoft.com/cli/azure/ad/sp?view=azure-cli-latest) as well considering using a [less privileged service principal account](https://learn.microsoft.com/azure/role-based-access-control/best-practices).

* Create a new Azure resource group where you want your cluster(s) to show up.

  ```shell
  az group create -l <Azure Region> -n <resource group name>
  ```

  For example:

  ```shell
  az group create -l eastus -n Arc-k8s-Clusters
  ```

  > **Note:** Currently, Azure Arc-enabled Kubernetes resource creation is supported in most, but not all, Azure regions.  Refer to [products available by region](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/?products=azure-arc&regions=all) for the latest list of supported regions. Use the --location (or -l) flag to specify one of these locations.

  ![Screenshot showing the Azure portal with empty resource group](./media/01.png)

* Change the following environment variables according to your Azure service principal name and Azure environment.

  If using shell:

  ```shell
  export appId='<Your Azure service principal name>'
  export password='<Your Azure service principal password>'
  export tenantId='<Your Azure tenant ID>'
  export resourceGroup='<Azure resource group name>'
  export arcClusterName='<The name of your k8s cluster as it will be shown in Azure Arc>'
  ```

  If using PowerShell:

  ```powershell
  $env:appId=<Your Azure service principal name>
  $env:password=<Your Azure service principal password>
  $env:tenantId=<Your Azure tenant ID>
  $env:resourceGroup=<Azure resource group name>
  $env:arcClusterName=<The name of your k8s cluster as it will be shown in Azure Arc>
  ```

## Getting Started

### Deployment

* Install the Azure Arc for Kubernetes CLI extension ***connectedk8s***:

  ```shell
  az extension add --name connectedk8s
  ```

  > **Note:** If you already used this Drop before and/or have the extension installed, use the below commands.

  ```shell
  az extension update --name connectedk8s
  ```

* Login to your Azure subscription.  

  If using shell:

  ```shell
  az login --service-principal --username $appId --password $password --tenant $tenantId
  ```

  If using PowerShell:

  ```powershell
  az login --service-principal --username $env:appId --password $env:password --tenant $env:tenantId
  ```

* To connect the Kubernetes cluster to Azure Arc use the below command.

  If using shell:

  ```shell
  az connectedk8s connect --name $arcClusterName --resource-group $resourceGroup --correlation-id "d009f5dd-dba8-4ac7-bac9-b54ef3a6671a"
  ```

  If using PowerShell:

  ```powershell
  az connectedk8s connect --name $env:arcClusterName --resource-group $env:resourceGroup --correlation-id "d009f5dd-dba8-4ac7-bac9-b54ef3a6671a"
  ```

Upon completion, you will have your Kubernetes cluster, connected as a new Azure Arc-enabled Kubernetes resource inside your resource group.

![Screenshot showing Azure ARM template deployment](./media/02.png)

![Screenshot showing the Azure portal with Azure Arc-enabled Kubernetes resource](./media/03.png)

![Screenshot showing the Azure portal with Azure Arc-enabled Kubernetes resource](./media/04.png)

### Delete the deployment

The most straightforward way is to delete the Azure Arc-enabled Kubernetes resource is via the Azure portal, just select cluster and delete it.

![Screenshot showing how to delete resources in the Azure portal](./media/05.png)

If you want to delete the entire environment, just delete the Azure resource group.

![Screenshot showing how to delete resource groups in the Azure portal](./media/06.png)

## Resources

For more information on Arc-enabled Kubernetes, refer to [What is Azure Arc-enabled Kubernetes?](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/overview)