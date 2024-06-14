# Overview
Azure Arc version 1.41 introduces certificate-based authentication for connecting and disconnecting servers, replacing the old method of using passwords. This new feature makes managing servers easier and more secure.

In this article, I will explain how to set up and use certificates for Azure Arc-enabled servers. You will learn how to create a certificate using Active Directory Certificate Services, export the certificate, and use it for onboarding servers to Azure Arc. Additionally, I will cover common issues you might face and suggest ways to improve the process.

By the end of this guide, you will be able to use certificates to securely manage and onboard your servers to Azure Arc.