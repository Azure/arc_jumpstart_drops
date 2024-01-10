---
type: docs
title: "Manage Extended Security Updates (ESU) licenses at scale"
linkTitle: "Manage Extended Security Updates (ESU) licenses at scale"
weight: 1
description: >
---

## Manage Extended Security Updates (ESU) licenses at scale

The following Jumpstart Drop will guide you on how to programatically perform tasks with on your [Extended Security Updates (ESU) licenses](https://learn.microsoft.com/windows-server/get-started/extended-security-updates-deploy) at scale.

This tool consists of a script that will allow you to:  

- Create ESU licenses for Azure Arc-enabled servers at scale
- Assign ESU licenses for Azure Arc-enabled servers

## Contributors

This Jumpstart Drop was originally written by the following contributors:

- [Raúl Carboneras | Cloud Solution Architect at Microsoft](https://www.linkedin.com/in/ra%C3%BAl-carboneras-37609350/)

## Prerequisites

- Clone the Azure Arc Drops repository

    ```shell
    git clone https://github.com/Azure/arc_jumpstart_drops.git
    ```

- The script requires PowerShell 7 as well as [Azure PowerShell](https://learn.microsoft.com/powershell/azure/install-azure-powershell?view=azps-11.1.0) installed.
- Before running the script you must run `Connect-AzAccount` and set the proper subscription with `Set-AzContext -Subscription xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxx`.
- It assumes Azure Arc-enabled Servers are already onboarded and registered in the Azure Portal.

## Getting Started

### Get ESU license information

The script uses a CSV file as input to create and assign licenses. To create a sample CSV file with your environment's information run the command below.

  ```powershell
   .\ESUsSetLicenses.ps1 -ReadOnly
  ```

This will create a 'ESULicensesSourcefile.csv' file  with the information of the recommended licenses to be created based on the Azure Arc-enabled servers that are connected to your subscription. Make sure to modify if needed based on your licensing needs.

### Create ESU Licenses

Once you have teh default CSV file you can use to create them or you can use a modified one. To create the ESU licenses for the Azure Arc-enabled servers using the default CSV use the command below:

  ```powershell
   .\ESUsSetLicenses.ps1 -ProvisionLicenses
  ```

To create the ESU licenses for the Azure Arc-enabled servers using a modified ModifiedESULicensesSourcefile.csv file run:

  ```powershell
   .\ESUsSetLicenses.ps1 -ProvisionLicenses -SourceLicensesFile 'ModifiedESULicensesSourcefile.csv'
  ```

As an output from this step you will get an 'ESUAssigmentInfo.csv' file with the information of the licenses created and the Azure Arc-servers to link to them. This file will be use as input for the next step.

### Assign the ESU licenses

Now that the licenses are asigned they need to be mapped to its corresponding Azure Arc-enabled server, using the 'ESUAssigmentInfo.csv' file or a modified one if you needed to make some changes.

  ```powershell
  .\ESUsSetLicenses.ps1 -AssignLicenses
  .\ESUsSetLicenses.ps1 -AssignLicenses -SourceLicenseAssigmentInfoFile ModifiedESUAssigmentInfo.csv
  ```

## Resources

Make sure to review the Jumpstart Scenario on ESU licenses for [Azure Arc-enabled Servers](https://azurearcjumpstart.com/azure_arc_jumpstart/azure_arc_servers/day2/arc_extended_security_updates) and [Azure Arc-enabled SQL Server.](https://azurearcjumpstart.com/azure_arc_jumpstart/azure_arc_sqlsrv/day2/esu/)