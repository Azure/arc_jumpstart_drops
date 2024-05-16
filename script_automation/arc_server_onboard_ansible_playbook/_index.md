---
type: docs
title: "Azure Arc onboarding using Ansible playbooks"
linkTitle: "Azure Arc onboarding using Ansible playbooks"
weight: 1
description: >
---

## Azure Arc onboarding using Ansible playbooks

The following Jumpstart Drop will guide you on how to use an Ansible playbook to onboard Linux and Windows VMs at scale.

> **Note:** This Jumpstart Drop provides the playbook to onboard into Azure Arc an existing VM inventory, if you don't have a set of VMs to onboard review the Jumpstart Scenario [Dynamic scaled onboarding of AWS EC2 instances to Azure Arc using Ansible](https://azurearcjumpstart.com/azure_arc_jumpstart/azure_arc_servers/scaled_deployment/aws_scaled_ansible) that will create VMs in AWS EC2 for you.

## Contributors

This Jumpstart Drop was originally written by the following contributors:

- [Dale Kirby | Principal Cloud Solution Architect at Microsoft](https://www.linkedin.com/in/dale-kirby/)
- [Laura Nicolás | Cloud Solution Architect at Microsoft](www.linkedin.com/in/lauranicolasd)

## Prerequisites

- Clone the Azure Arc Drops repository

    ```shell
    git clone https://github.com/Azure/arc_jumpstart_drops.git
    ```

- [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)

- Create Azure service principal (SP)

    To be able to complete the Drop and its related automation, Azure service principal assigned with the “Contributor” role is required. To create it, login to your Azure account run the below command (this can also be done in [Azure Cloud Shell](https://shell.azure.com/).

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

- [Ansible must be configured to interact with your inventory.](https://docs.ansible.com/ansible/latest/getting_started/get_started_inventory.html#get-started-inventory)

## Getting Started

### Editing the playbook and hosts file

Open the playbook using an editor and provide the values for the environment variables to match your environment. You will need to provide:

- `service_principal_id`: provide-your-service-principal-id-here.
- `service_principal_secret`: provide-your-service-principal-secret-here.
- `tenant_id`: provide-your-tenant-id-here.
- `subscription_id`: provide-your-subscription-id-here'
- `resource_group`: provide-your-resource-group-here.
- `location`: provide-your-location-here.

Edit the hosts file to add the hostnames of the server's you want to onboard to Ansible. You could also work with an [Ansible dynamic inventory.](https://docs.ansible.com/ansible/latest/inventory_guide/intro_dynamic_inventory.html)

### Run the automation

Once you have provided your inputs, run the playbook with the command below:

```bash
ansible-playbook arc-server-onboard-ansible-playbook.yml -i hosts
```

## Resources

For more information about at scale onboarding to Azure Arc, review the following resources:

- [Connect machines at scale using Ansible playbooks](https://learn.microsoft.com/azure/azure-arc/servers/onboard-ansible-playbooks)
- Dynamic scaled onboarding of AWS EC2 instances to Azure Arc using Ansible [Jumpstart scenario](https://azurearcjumpstart.com/azure_arc_jumpstart/azure_arc_servers/scaled_deployment/aws_scaled_ansible)
- AWS EC2 scaled onboarding with Azure Arc enabled servers using Ansible [video](https://www.youtube.com/watch?v=0Eb2j8XlxUQ&t=15s)
