## Edge Storage Accelerator (ESA) Single Node K3s on Ubuntu
This example can be used to install ESA on an Ubuntu system with K3s. 

> ⚠️ **Disclaimer:** The Edge Storage Accelerator is currently in public preview and not generally available. Access to the feature may be limited and subject to specific terms and conditions. For further details and updates on availability, please refer to the [Edge Storage Accelerator Documentation](https://learn.microsoft.com/azure/azure-arc/edge-storage-accelerator/overview).

## Overview
![Edge Storage Accelerator Diagram.](esa_diagram.PNG)

## Prerequisites
* Ubuntu 22.04 or similar VM or hardware that meets [ESA requirements](https://learn.microsoft.com/en-us/azure/azure-arc/edge-storage-accelerator/prepare-linux#minimum-hardware-requirements)
  * Standard_D8ds_v4 VM recommended
  * Equivalent specifications per node:
    * 4 CPUs
    * 16GB RAM
  * 14G of free disk space in /var

* Installation of [K3s](https://docs.k3s.io/quick-start)

* Create a [Storage Account and container](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal)

## Getting Started
Use the following table to determine the values to be used in the export block below. If you exit your shell during configuration before you have completed all the steps, you must re-export the variables before continuing.  

|Variable        | Required Parameter                                             | Example |
|----------------|----------------------------------------------------------------|-----------------|
|REGION          | Azure Region you wish to deploy in                             | eastus          |
|RESOURCE_GROUP  | The Resource Group you created with the storage account in it  | myResourceGroup |
|SUBSCRIPTION    | The Azure Subscription ID you are using                        | nnnn-nnnnnnn-nnn|
|ARCNAME         | The name you would like your ARC cluster to be called in Azure | myArcClusterName|
|STORAGEACCOUNT  | The name of the storage account you created                    | myStorageAccount|
|STORAGECONTAINER| The name of the container you created in your storage account  | nameOfContainer |

```bash
export REGION="eastus"
export RESOURCE_GROUP="myResourceGroup"
export SUBSCRIPTION="your-subscription-id-here"
export ARCNAME="myArcClusterName" # will be used as displayname in portal
export STORAGEACCOUNT="myStorageAccountName"
export STORAGECONTAINER="nameOfContainerInStorageAccount"
```
#### Apply inotify.max_user_instance increase
Apply this change to increase the inotify space for your Ubuntu system: 

```bash
echo 'fs.inotify.max_user_instances = 1024' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

#### Arc Connect Kubernetes
This command connects your Kubernetes cluster to Azure Arc for management and access to Azure Arc Extensions. 
```bash
az connectedk8s connect -n ${ARCNAME} -l ${REGION} -g ${RESOURCE_GROUP} --subscription ${SUBSCRIPTION}
```
#### Install Open Service Mesh
Open Service Mesh is used to secure connections between ESA components in the Kubernetes cluster. 
```bash
az k8s-extension create --resource-group ${RESOURCE_GROUP} --cluster-name ${ARCNAME} --cluster-type connectedClusters --extension-type Microsoft.openservicemesh --scope cluster --name osm
```
#### Install Edge Storage Accelerator
This command will install the ESA Extension on to your Kubernetes cluster via Azure Arc.

```bash
az k8s-extension create --resource-group "${RESOURCE_GROUP}" --cluster-name "${ARCNAME}" --cluster-type connectedClusters --name esa --extension-type microsoft.edgestorageaccelerator --config-file config.json
```
#### Configure ESA 
For this example, the components are separate and applied separately to the Kubernetes cluster to create the volume entities for ESA, however you can chose to combine them into a single yaml to reduce the number of config files you have to maintain. 

```bash
bash get_storage_key.sh -g ${RESOURCE_GROUP} -s ${STORAGEACCOUNT} -n "default"
cat pv.template.yaml | sed "s/STORAGEACCOUNT/$STORAGEACCOUNT/g" | sed "s/STORAGECONTAINER/$STORAGECONTAINER/g" > pv.yaml
kubectl apply -f pv.yaml
kubectl apply -f pvc.yaml
kubectl apply -f examplepod.yaml
```

#### Attach to example pod to use /mnt/esa
This block is used to determine the name of the dynamic Microsoft Linux POD that is mounted to the ESA volume and to start a Bash shell for you to experiment with the filesystem. This Linux host can be leveraged for any ESA testing. 

```bash
example_pod=`kubectl get pod -o yaml | grep name | head -1 | awk -F ':' '{print $2}'`
kubectl exec -it ${example_pod} -- bash
```

For help, visit https://learn.microsoft.com/en-us/azure/azure-arc/edge-storage-accelerator
