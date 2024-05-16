---
type: docs
title: "Test Azure Arc-enabled servers on a Windows Azure VM"
linkTitle: "Test Azure Arc-enabled servers on a Windows Azure VM"
weight: 1
description: >
---

## Test Azure Arc-enabled servers on a Windows Azure VM

The following Jumpstart Drop will guide you on how to project an existing Windows Azure VM as an Azure Arc-enabled server in an automated fashion using a PowerShell script. Note that onboarding an Azure VM as an Azure Arc-enabled server isn't supported and this automation is intended for demo and testing purposes only.

> **Note:** It's not expected for an Azure VM to be projected as an Azure Arc-enabled server. The Jumpstart Drop  is unsupported and should ONLY be used for demo and testing purposes.

> **Note:** This Jumpstart Drop provides the script to onboard an existing Azure VM, if you don't have an existing virtual machine, review the Jumpstart Scenario [Deploy a Windows Azure Virtual Machine and connect it to Azure Arc using an ARM Template](https://azurearcjumpstart.com/azure_arc_jumpstart/azure_arc_servers/azure/azure_arm_template_win) that will create it for you.

## Contributors

This Jumpstart Drop was originally written by the following contributors:

- [Laura Nicolás | Cloud Solution Architect at Microsoft](www.linkedin.com/in/lauranicolasd)

## Prerequisites

- Clone the Azure Arc Drops repository

    ```shell
    git clone https://github.com/Azure/arc_jumpstart_drops.git
    ```

- [Install or update Azure CLI to version 2.53.0 and above](https://learn.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest). Use the below command to check your current installed version.

  ```shell
  az --version
  ```

- In case you don't already have one, you can [Create a free Azure account](https://azure.microsoft.com/free/).

- Create Azure service principal (SP)

    To be able to complete the scenario and its related automation, Azure service principal assigned with the “Contributor” role is required. To create it, login to your Azure account run the below command (this can also be done in [Azure Cloud Shell](https://shell.azure.com/).

    ```shell
    az login
    subscriptionId=$(az account show --query id --output tsv)
    az ad sp create-for-rbac -n "<Unique SP Name --role "Contributor" --scopes /subscriptions/$subscriptionId
    ```

    For example:

    ```shell
    az login
    subscriptionId=$(az account show --query id --output tsv)
    az ad sp create-for-rbac -n "JumpstartArc" --role "Contributor" --scopes /subscriptions/$subscriptionId
    ```

    Output should look like this:

    ```json
    {
    "appId": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "displayName": "JumpstartArc",
    "password": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "tenant": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    }
    ```

    > **Note:** If you create multiple subsequent role assignments on the same service principal, your client secret (password) will be destroyed and recreated each time. Therefore, make sure you grab the correct password.

    > **Note:** The Jumpstart drops are designed with as much ease of use in-mind and adhering to security-related best practices whenever possible. It's optional but highly recommended to scope the service principal to a specific [Azure subscription and resource group](https://learn.microsoft.com/cli/azure/ad/sp?view=azure-cli-latest) as well considering using a [less privileged service principal account](https://learn.microsoft.com/azure/role-based-access-control/best-practices).

- Azure Arc-enabled servers depends on the following Azure resource providers in your subscription in order to use this service. Registration is an asynchronous process, and registration may take approximately 10 minutes.

  - `Microsoft.HybridCompute`
  - `Microsoft.GuestConfiguration`
  - `Microsoft.HybridConnectivity`

      ```shell
      az provider register --namespace 'Microsoft.HybridCompute'
      az provider register --namespace 'Microsoft.GuestConfiguration'
      az provider register --namespace 'Microsoft.HybridConnectivity'
      ```

      You can monitor the registration process with the following commands:

      ```shell
      az provider show --namespace 'Microsoft.HybridCompute'
      az provider show --namespace 'Microsoft.GuestConfiguration'
      az provider show --namespace 'Microsoft.HybridConnectivity'
      ```

## Getting Started

### Editing the script

Open the script using an editor and provide the values for the environment variables to match your environment. You will need to provide:

- `subscriptionId`: Provide your subscription ID
- `appId`: Provide your Service Principal App ID
- `password`: Provide your service principal password
- `tenantId`: Provide your Tenant ID
- `resourceGroup`: Provide your resource group name
- `location`: Provide the Azure Region

### Run the automation

Once you have provided your inputs, run the script with the command below:

```powershell
.\windows_arc_onboarding.ps1
```

## Resources

For more information about onboarding Azure VMs to Azure Arc, review the following resources:

- [Evaluate Azure Arc-enabled servers on an Azure virtual machine](https://learn.microsoft.com/azure/azure-arc/servers/plan-evaluate-on-azure-virtual-machine)
- Manual Ubuntu server onboarding with Azure Arc-enabled servers [video](https://www.youtube.com/watch?v=F_0w_fEqx6Y&list=PLZuSmETs0xIauYQB1UeyZbBGhdj7BREOG&index=7)
- Jumpstart Scenario on how to [Deploy a Linux Azure Virtual Machine and connect it to Azure Arc using an ARM Template](https://azurearcjumpstart.com/azure_arc_jumpstart/azure_arc_servers/azure/azure_arm_template_linux).
