---
type: docs
title: "Azure Stack HCI - IaC Template Examples"
linkTitle: "This Drop provides examples of Infrastructure as Code (IaC) templates for Deploying Azure Stack HCI."
weight: 1
description: >
---

## Azure Stack HCI - IaC Template Examples

This drop provides example of Infrastructure as Code (IaC) templates for Deploying Azure Stack HCI. The templates are written in ARM and Bicep and can be used to deploy Azure Stack HCI clusters in Azure in a Scalable manner
> **Note:**  The Jumpstart Drop is unsupported and should ONLY be used for demo, testing and learning purposes.

> **Note:** This Jumpstart Drop provides the script to onboard an Azure Stack HCI Cluster, you will need to ensure you have completed all PreRequisites of Azure Stack HCI Cloud Deployment before deploying. [Deploy Azure Stack HCI 23H2](https://learn.microsoft.com/en-us/azure-stack/hci/deploy/deployment-introduction)..

## Contributors

This Jumpstart Drop was originally written by the following contributors:

- [Michael Godfrey | Senior Program Manager at Microsoft](https://www.linkedin.com/in/migodfre)

## Prerequisites

- Clone the Azure Arc Drops repository

    ```shell
    git clone https://github.com/Azure/arc_jumpstart_drops.git
    ```

- Completion of [Register your servers with Azure Arc and assign deployment permissions](https://learn.microsoft.com/en-us/azure-stack/hci/deploy/deployment-arc-register-server-permissions). Make sure that:
    - All the mandatory extensions are installed successfully. The mandatory extensions include: **Azure Edge Lifecycle Manager**, **Azure Edge Device Management**, and **Telemetry and Diagnostics**.
    - All servers are running the same version of OS.
    - All the servers have the same network adapter configuration.

- Prepare Azure Resources
  - [Ensure you have a Service Principal with Correct Subscription and Resource Group Permissions](https://learn.microsoft.com/en-us/azure-stack/hci/deploy/deployment-azure-resource-manager-template#create-a-service-principal)
  - [Pre-Create Cloud Witness Storage Account](https://learn.microsoft.com/en-us/azure-stack/hci/deploy/deployment-azure-resource-manager-template#create-a-cloud-witness-storage-account)
  - [Encode Parameter Values](https://learn.microsoft.com/en-us/azure-stack/hci/deploy/deployment-azure-resource-manager-template#encode-parameter-values)
  - [Assign Resource Permissions ](https://learn.microsoft.com/en-us/azure-stack/hci/deploy/deployment-azure-resource-manager-template#step-2-assign-resource-permissions)

## Getting Started

### Prepare Parameter File
- In order to Deploy the ASHCI Cluster you will need to create a Parameter File with Values that apply to your Environment. Make a copy of the parameter file that applies to your chosen ASHCI Network Configuration, In this Jumpstart DROP, three common examples are provided:
    - [2 Node Switch less](script_automation/arc_ashci_iac/artifacts/Templates/ARM/ASHCI-CloudDeploy-2NodeSwitchless.parameters.json)
    - [3 Node Switch less](script_automation/arc_ashci_iac/artifacts/Templates/ARM/ASHCI-CloudDeploy-3NodeSwitchless.parameters.json)
    - [Fully Converged](script_automation/arc_ashci_iac/artifacts/Templates/ARM/ASHCI-CloudDeploy-FullyConverged.parameters.json) 

### Editing the Parameters File

Open the selected Parameter File using an editor and provide the values for the environment variables to match your environment. You will need to provide:

- `DeploymentMode`: Choose between **Validate** & **Deploy**, your first deployment will always use the Validate Variable.
- `KeyVaultName`: Provide the name of the Azure Key Vault that will be created to store ASHCI Cloud Deployment Secrets
- `softDeleteRetentionDays`: Number of Days Azure Key Vault will be retained in case of Deletion (Optional)
- `diagnosticStorageAccountName`: Name of Azure Storage Account that will be used for Diagnostic Logs associated with the Azure Key Vault
- `logsRetentionInDays`: Number of Days Key Vault Diagnostics will be retained (Optional)
- `storageAccountType`: Azure Storage Account Type
- `secretsLocation`: URI to Azure Key Vault, this should match the name of your Key Vault
- `ClusterWitnessStorageAccountName`: Name of Cloud Witness Azure Storage Account that was created in PreRequisites
- `ClusterName`: Active Directory Name of the Desired ASHCI Cluster
- `Location`: Provide the Azure Region
- `TenantID`: Provide your Tenant ID
- `localAdminSecretValue`: This should be base64 value in UserName:Password format of the Local Administrator Account
- `domainAdminSecretValue`: This should be base64 value in UserName:Password format of the AD Service Account used to Join Domain, Create Cluster, etc.
- `arbDeploymentSpnValue`: Azure EntraID SPN Account from Prerequisites, as a base64 value in ApplicationID:Client Secret format.
- `storageWitnessValue`: This should be base64 value of the Storage Account Access Key in StorageAccountKey format.
- `arcNodeResourceIds`: Provide the Arc-Enabled Machine Resource ID of all the ASHCI nodes
- `domainFqdn`: Fully Qualified Domain Name that ASHCI Cluster will be deployed into
- `namingPrefix`: Prefix for all ASHCI Infra Resources that will be created. 
- `adouPath`: Provide OU to place AHSCI Cluster and Node Computer Objects
- `subnetMask`: subnet mask of Management Network
- `defaultGateway`: Gateway IP of Management Network
- `startingIPAddress`: Starting Address for IP Range for ASHCI Infra Services (Requires 6 Consecutive IP Addresses)
- `endingIPAddress`: Ending Address for IP Range for ASHCI Infra Services
- `dnsServers`: IP Addresses of DNS Servers in Array Format
- `physicalNodesSettings`: Array Table of ASHCI Node Names and Assigned IP Address
- `intentList`: Array Table of ASHCI NetworkATC Intent. The Adapter array needs to be updated with the Consistent Network Adapter names across all ASHCI Nodes
- `storageNetworkList`: Name of Storage Networks, the Network Adapter Names, and the Associated VLAN Tag
- `CustomLocation`: The Name of your ASHCI Location, this will be the value that workloads (VM/AKS/AVDonHCI/etc will be deployed to. This is similar to Azure Region)


### Deploy using ARM template

With all the prerequisite and preparation steps complete, you're ready to deploy using a known good and tested ARM deployment template and corresponding parameters JSON file. Use the parameters contained in the JSON file to fill out all values, including the encoded values generated previously. 

> [!IMPORTANT] 
> In this release, make sure that all the parameters contained in the JSON value are filled out including the ones that have a null value. If there are null values, then those need to be populated or the validation fails.

1. In Azure portal, go to **Home** and select **+ Create a resource**.

1. Select **Create** under **Template deployment (deploy using custom templates)**
    ![Screenshot showing the template deployment (deploy using custom template).](./artifacts/media/deployment-azure-resource-manager-template/deploy-arm-template-1.png)        

1. Near the bottom of the page, find **Start with a quickstart template or template spec** section. Select **Quickstart template** option.
    ![Screenshot showing the quickstart template selected.](./artifacts/media/deployment-azure-resource-manager-template/deploy-arm-template-2.png)
   
1. Use the **Quickstart template (disclaimer)** field to filter for the appropriate template. Type *azurestackhci/create-cluster* for the filter.

1. When finished, **Select template**.
    ![Screenshot showing template selected](./artifacts/media/deployment-azure-resource-manager-template/deploy-arm-template-3.png)

1. On the **Basics** tab, you see the **Custom deployment** page. You can select the various parameters through the dropdown list or select **Edit parameters**.
     ![Screenshot showing Custom deployment page on the Basics tab.](./artifacts/media/deployment-azure-resource-manager-template/deploy-arm-template-4.png)

1. Edit parameters such as network intent or storage network intent. Once the parameters are all filled out, **Save** the parameters file.
    ![Screenshot showing parameters filled out for the template.](./artifacts/media/deployment-azure-resource-manager-template/deploy-arm-template-5.png)

1. Select the appropriate resource group for your environment.

1.  Scroll to the bottom, and confirm that **Deployment Mode = Validate**.

1. Select **Review + create**.
   ![Screenshot showing Review + Create selected on Basics tab.](./artifacts/media/deployment-azure-resource-manager-template/deploy-arm-template-6.png)

1. On the **Review + Create** tab, select **Create**. This creates the remaining prerequisite resources and validates the deployment. Validation takes about 10 minutes to complete.
    ![Screenshot showing Create selected on Review + Create tab.](./artifacts/media/deployment-azure-resource-manager-template/deploy-arm-template-7.png)

1.  Once validation is complete, select **Redeploy**.
     ![Screenshot showing Redeploy selected](./artifacts/media/deployment-azure-resource-manager-template/deploy-arm-template-7a.png)

1. On the **Custom deployment** screen, select **Edit parameters**. Load up the previously saved parameters and select **Save**.

1. At the bottom of the workspace, change the final value in the JSON from **Validate** to **Deploy**, where **Deployment Mode = Deploy**. 
     ![Screenshot showing deploy selected for deployment mode.](./artifacts/media/deployment-azure-resource-manager-template/deploy-arm-template-7b.png)

1. Verify that all the fields for the ARM deployment template have been filled in by the Parameters JSON.

1. Select the appropriate resource group for your environment.

1. Scroll to the bottom, and confirm that **Deployment Mode = Deploy**.

1. Select **Review + create**.

1. Select **Create**. This begins deployment, using the existing prerequisite resources that were created during the **Validate** step.

    The Deployment screen cycles on the Cluster resource during deployment.

    Once deployment initiates, there's a limited Environment Checker run, a full Environment Checker run, and cloud deployment starts. After a few minutes, you can monitor deployment in the portal.

   ![Screenshot showing the status of environment checker validation.](./artifacts/media/deployment-azure-resource-manager-template/deploy-arm-template-9.png)

1. In a new browser window, navigate to the resource group for your environment. Select the cluster resource.

1. Select **Deployments**.

1. Refresh and watch the deployment progress from the first server (also known as the seed server and is the first server where you deployed the cluster). Deployment takes between 2.5 and 3 hours. Several steps take 40 to 50 minutes or more.

    > [!NOTE]
    > If you check back on the template deployment, you will see that it eventually times out. This is a known issue, so watching **Deployments** is the best way to monitor the progress of deployment.

1. The step in deployment that takes the longest is **Deploy Moc and ARB Stack**. This step takes ~40 to 45 minutes.

    Once complete, the task at the top updates with status and end time.

### Next Steps
 Now that your Azure Stack HCI Cluster is built you can move on to the next steps which include:

1. [Download Azure Marketplace Images](https://learn.microsoft.com/en-us/azure-stack/hci/manage/virtual-machine-image-azure-marketplace)
1. [Download Custom Images](https://learn.microsoft.com/en-us/azure-stack/hci/manage/virtual-machine-image-local-share)
1. [Create Logical Networks](https://learn.microsoft.com/en-us/azure-stack/hci/manage/create-logical-networks?tabs=azurecli)

After these steps have been completed you can begin work on deploying Workloads.
1. [Deploy Arc Virtual Machines](https://learn.microsoft.com/en-us/azure-stack/hci/manage/create-arc-virtual-machines?tabs=azurecli)
1. [Deploy AKS-Arc Clusters](https://learn.microsoft.com/en-us/azure/aks/hybrid/aks-create-clusters-portal)




