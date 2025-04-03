---
type: docs
title: "Azure Arc SQL Tags Inheritance"
linkTitle: "Azure Arc SQL Tags Inheritance"
weight: 1
description: >
---

## Overview  
Ensure Azure Arc SQL Instances inherit tags from the associated Azure Arc VM, addressing the default behavior where SQL Instances do not replicate tags. This improves resource management and consistency in the Azure environment.

## Getting Started

This repository contains the **Azure Arc SQL Instance - Tag Inheritance** script, designed to resolve **tag management inconsistencies** in scenarios with **SQL machines integrated with Azure Arc**.

### Why Use This Script?  
By default, Azure Arc SQL Instances do not inherit tags from the associated Azure Arc VM, complicating resource management. This script ensures the tags from the VM are replicated to the SQL Instance, promoting better organization and consistency in your Azure environment.

## Deploying Artifacts

The script **`AzureArcSQLTags-Inheritance.ps1`** can be used in a **runbook** and is available in the **scripts** folder of this repository. You can access it directly at the following link:  
[AzureArcSQLTags-Inheritance.ps1](https://raw.githubusercontent.com/fabiotreze/AzureArcBRTips/refs/heads/main/azure_arc_jumpstart_drops/script_automation/AzureArcSQLTags-Inheritance/AzureArcSQLTags-Inheritance.ps1).

### Prerequisites

### Automation Account
- The **Az.Account** and **Az.ResourceGraph** modules must be installed for the script to work correctly.  
- A **managed identity** must be configured for the Automation Account, enabling secure access to the required resources in Azure.  

### Runbook
- A **schedule** for the **runbook** must be configured, ensuring the script runs automatically at predefined intervals.  

### Parameters

The script requires the following parameters:

- **ResourceGroupName**: The name of the resource group where the Azure Arc SQL Instance and the associated VM are located.  
- **SubscriptionID**: The ID of the Azure subscription where the resources are registered.  
- **tagName**: The name of the tag to be applied to the Azure Arc SQL Instance, based on the tags configured on the associated VM.  

### What Does This Solve?
These parameters ensure that the tags are properly synchronized between the Azure Arc resources and their related VMs, promoting more efficient and organized resource management. 

### Note
Make sure your Automation Account and Azure resources are correctly configured before running the script.

## Contributions

Contributions are welcome! Feel free to open an _issue_ or submit a _pull request_ to improve this repository.
