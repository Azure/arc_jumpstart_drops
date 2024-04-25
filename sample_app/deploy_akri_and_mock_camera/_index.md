---
type: docs
title: "Deploy Akri on an Azure Arc-enabled Kubernetes cluster with an IP mock camera"
linkTitle: "Deploy Akri on an Azure Arc-enabled Kubernetes cluster with an IP mock camera"
weight: 1
description: >
---

## Deploy Akri on an Azure Arc-enabled Kubernetes cluster with an IP mock camera

The following Jumpstart Drop will guide you on how to deploy Akri as Kubernetes resource interface that exposes an IP mock camera in an Azure Arc-enabled Kubernetes cluster.

Akri is an open source project for a Kubernetes resource interface that lets you expose heterogenous leaf devices as resources in a Kubernetes cluster. It currently supports OPC UA, ONVIF, and udev protocols, but you can also implement custom protocol handlers provided by the template. In this drop, Akri is used for handling the dynamic appearance and disappearance of an ONVIF mock camera as the Discovery Handler.

## Contributors

This Jumpstart Drop was originally written by the following contributors:

- [Francisco Cabrera | Senior Technical Program Manager at Microsoft](https://www.linkedin.com/in/franciscocabreralieutier/)
- [Laura Nicolás | Cloud Solution Architect at Microsoft](www.linkedin.com/in/lauranicolasd)

## Prerequisites

- Clone the Azure Arc Drops repository

    ```shell
    git clone https://github.com/Azure/arc_jumpstart_drops.git
    ```

- [Install Helm](https://helm.sh/docs/helm/helm_install/)

- Install [AKS Edge Essentials](https://learn.microsoft.com/en-us/azure/aks/hybrid/aks-edge-quickstart)

## Getting Started

### Run the automation

This drop deploys Akri and it is used to discover ONVIF cameras that are connected to the same network as your cluster, in this instance a mock ONVIF camera is deployed as a container. These steps help you get started using Akri to discover IP cameras through the ONVIF protocol and use them via a video broker that enables you to consume the footage from the camera and display it in a web application.

Navigate to the [deployment folder](https://raw.githubusercontent.com/Azure/arc_jumpstart_drops/main/drops/sample_app/deploy_akri_and_mock_camera/) and run:

  ```powershell
    . .\akri_deploy.ps1
  ```

### Verify the deployment

First, verify that Akri can discover the camera, it should be seen as one Akri instance that represents the ONVIF camera:

  ```shell
    kubectl get akrii
  ```

Then get the port of the web app service by running:

  ```shell
    kubectl get svc
  ```

Open a web browser and navigate to the web app service URL to watch the video streaming.