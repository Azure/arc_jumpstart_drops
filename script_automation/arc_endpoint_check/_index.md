---
type: docs
title: "Azure Arc Connectivity Check"
linkTitle: "Azure Arc Connectivity Check"
weight: 1
description: >
---

## Overview  

This script was created to help identify connectivity issues with the Azure Arc Machine Agent and its endpoints. It tests the necessary URLs, validates Azure Arc functionality, and performs DNS resolution, network connectivity, and HTTP request checks, logging the results for review.

## Prerequisites

- PowerShell
- Network connectivity 

## Getting Started

Download the [ArcEndpointCheck.ps1](./ArcEndpointCheck.ps1) and follow these steps to set up and use the script:

1. **Define the Region**  
   Set the region for your Azure Arc deployment. For example:  
   `$region = "brazilsouth"`

2. **Define the Log File Path**  
   Specify the location where the log file will be saved. For example:  
   `$logFilePath = "C:\temp\Arclogfile.txt"`

3. **Choose Public or Private Deployment**  
   Determine whether your Azure Arc instance will be public or private.  
   If you're using a public deployment, make sure to remove the `--enable-pls-check` parameter from the script.

## Using the Script

Execute the script on the server where the Azure Arc Agent will be installed. When running the script, keep in mind environmental factors such as firewall settings, proxy configuration, region, and whether the connection is public or private. Make the necessary adjustments in the script to account for these aspects. The script includes a check with `AzcmAgent.exe`, so ensure that the Azure Arc Agent is already installed on the server before running it.

## Contributions

Contributions are welcome! Feel free to open an _issue_ or submit a _pull request_ to improve this repository.