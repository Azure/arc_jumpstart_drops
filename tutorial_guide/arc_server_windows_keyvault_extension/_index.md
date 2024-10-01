## Overview
Managing certificates across multiple servers in a hybrid environment can be a complex and time-consuming task. Whether you’re securing a website with HTTPS or authenticating to another server, the need for secure deployment and renewal of certificates is constant. This challenge becomes even more daunting when you need to share the same certificate across numerous servers. To address these issues, the Azure Key Vault certificate sync extension for Arc-enabled servers offers a streamlined solution

By the end of this guide, you will be able to securely acquire and manage certificates using the Azure Key Vault extension on your Azure Arc-enabled servers

![](./media/image001.png#center)

## Key Advantages  
Here are some key advantages of using this extension:

- **Centralized Management:** The Azure Key Vault extension allows for centralized management of certificates, simplifying the process of keeping them up to date across multiple servers.
- **Ease of Deployment:** Instead of manually copying certificates to each server, administrators can upload or generate certificates in Key Vault and configure server access, streamlining deployment.
- **Enhanced Security:** The use of managed identities for authentication ensures secure access to Azure Key Vault, enhancing the overall security of the certificate management process.
- **Streamlined Renewal operations:** You can setup alerts to be notified for upcoming certificate expiration, also you can add the latest version of a certificate and the extension will pull it.

## Prerequisites

Ensure you have the following:

- An Azure subscription.
- An Azure Key Vault with the necessary permissions (detailed below).
- Azure Arc-enabled Windows servers.
- Azure PowerShell module installed.

## Azure Key Vault Permissions

Each Arc-enabled server comes with a system-assigned managed identity. This identity is used by the Azure Key Vault extension to authenticate with your vault and retrieve certificates. To function properly, each Arc-enabled server requires GET and LIST permissions on the secrets in your Key Vault. The Key Vault Certificate User RBAC role is ideal for this purpose, adhering to the principle of least privilege.

![](./media/image007.png#center)

For larger deployments, it’s advisable to group your Arc-enabled server identities into an Microsoft Entra security group and grant this group access to the vault.

## Install the Azure Key Vault extension on Arc-enabled Windows servers

1. **Log in to Azure**

Log in to your Azure account using the Azure PowerShell module:

```PowerShell
Connect-AzAccount
```

2. **Define the Settings**

First, define the settings for secrets management and authentication. This includes specifying the Key Vault/Certificate URI, the certificate store location on the Arc-enabled server where the certificate will be stored, and the polling interval.

```PowerShell
$Settings = @{
  secretsManagementSettings = @{
    observedCertificates = @(
      "https://MYKEYVAULT.vault.azure.net/secrets/MYCERTIFICATE"
      # Add more here in a comma separated list
    )
    certificateStoreLocation = "LocalMachine"
    certificateStoreName = "My"
    pollingIntervalInS = "3600" # every hour
  }
  authenticationSettings = @{
    # Don't change this line, it's required for Arc enabled servers
    msiEndpoint = "http://localhost:40342/metadata/identity"
  }
}
```
Both the Key Vault and certificate name that constructs the URI can be retrieved as illustrated below by navigating to the Azure Portal, Azure Key Vault, and then Certificates.

![](./media/image004.png#center)

3. **Install Azure Key Vault extension**

Next, set the variables for your resource group where the Arc-enabled machine is contained, specify the Arc-enabled machine name, and lastly, the location.

```PowerShell
$ResourceGroup = "myrg"
$ArcMachineName = "myarcsrv01"
$Location = "westeurope"
```

Use the New-AzConnectedMachineExtension cmdlet to install the Key Vault extension on your Arc-enabled server.

```PowerShell
# Check if the Az.ConnectedMachine module is installed
if (-not (Get-Module -ListAvailable -Name Az.ConnectedMachine)) {
    Write-Host "Az.ConnectedMachine module is not installed. Installing now..."
    Install-Module -Name Az.ConnectedMachine -Scope CurrentUser -Force
} else {
    Write-Host "Az.ConnectedMachine module is already installed."
}

# Install the Azure Key Vault extension on Arc-enabled Windows server
New-AzConnectedMachineExtension -ResourceGroupName $ResourceGroup -MachineName $ArcMachineName -Name "KeyVaultForWindows" -Location $Location -Publisher "Microsoft.Azure.KeyVault" -ExtensionType "KeyVaultForWindows" -Setting $Settings
```


The script first checks if the Az.ConnectedMachine module is installed. If it isn’t, the script installs the module. After ensuring the required modules are installed, you can manually proceed to install the Azure Key Vault extension on an Arc-enabled Windows server and configure it with the previously defined settings.

Finally, you will see that the server has been successfully onboarded..

![](./media/image005.png#center)


## Confirming

A few minutes after the extension is installed, check the Arc-enabled server’s certificate store. You should see that the server has successfully acquired the certificate!

![](./media/image006.png#center)


## Conclusion
By following these steps, you can easily manage and acquire certificates from Azure Key Vault on your Arc-enabled Windows servers. This not only ensures your applications remain secure and compliant but also streamlines the lifecycle management of certificates, making it easier to handle renewals and updates.
