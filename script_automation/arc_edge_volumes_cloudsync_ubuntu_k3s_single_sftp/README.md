# Azure Container Storage enabled by Azure Arc: Cloud Ingest Edge Volume on a Single Node Ubuntu K3s Cluster with an SFTP Front End

This example can be used to install Azure Container Storage enabled by Azure Arc to provide a ReadWriteMany Cloud Ingest Edge Volume on an Ubuntu system with K3s and an SFTP front end. This allows you all the functionality of the base product as well as being able to accept writes from SFTP clients. 
Cloud Ingest edge volumes will transfer files saved to the volume to cloud and purge the local copy, according to your ingest policy. 

> ⚠️ **Disclaimer:** Azure Container Storage enabled by Azure Arc: Edge Volumes is currently in public preview. Access to the feature is limited and subject to specific terms and conditions. For further details and updates on availability, please refer to the [Azure Container Storage enabled by Azure Arc Documentation](https://learn.microsoft.com/azure/azure-arc/container-storage/).

## Architecture

![Azure Container Storage enabled by Azure Arc Diagram.](./acsaedgevolarch.png)

## Prerequisites

* Ubuntu 22.04 or similar VM or hardware that meets [ACSA requirements](https://learn.microsoft.com/azure/azure-arc/container-storage/prepare-linux#minimum-hardware-requirements)
  * Standard_D8ds_v4 VM recommended
  * Equivalent specifications per node:
    * 4 CPUs
    * 16GB RAM
  * 14G of free disk space in /var

* Installation of [K3s](https://docs.k3s.io/quick-start)

A sample [setup_env.sh](./setup_env.sh) script is included in the Jumpstart Repository as a guide. 

## Getting Started

### Set your environment variables
Use the following table to determine the values to be used in the export block below. If you exit your shell during configuration before you have completed all the steps, you must re-export the variables before continuing.  

|Variable        | Required Parameter                                             | Example |
|----------------|----------------------------------------------------------------|-----------------|
|REGION          | Azure Region you wish to deploy in                             | eastus          |
|RESOURCE_GROUP  | The Resource Group you created with the storage account in it  | myResourceGroup |
|SUBSCRIPTION    | The Azure Subscription ID you are using                        | nnnn-nnnnnnn-nnn|
|ARCNAME        | The name you would like your ARC cluster to be called in Azure | myArcClusterName|
|STORAGEACCOUNT  | The name of the storage account you created                    | myStorageAccount|

```bash
export REGION="eastus"
export RESOURCE_GROUP="myResourceGroup"
export SUBSCRIPTION="your-subscription-id-here"
export ARCNAME="myArcClusterName"
export STORAGEACCOUNT="myStorageAccountName"
```

### Apply inotify.max_user_instance increase

Apply this change to increase the inotify space for your Ubuntu system: 

```bash
echo 'fs.inotify.max_user_instances = 1024' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Arc Connect Kubernetes

```bash
az connectedk8s connect -n ${ARCNAME} -l ${REGION} -g ${RESOURCE_GROUP} --subscription ${SUBSCRIPTION}
```

### Install package for certificate management

```bash
az k8s-extension create --cluster-name "${ARCNAME}" --name "${ARCNAME}-certmgr" --resource-group "${RESOURCE_GROUP}" --cluster-type connectedClusters --release-train preview --extension-type microsoft.iotoperations.platform --scope cluster --release-namespace cert-manager
```

### Install Azure Container Storage enabled by Azure Arc Extension with Config CRD creation

```bash
az k8s-extension create --resource-group "${RESOURCE_GROUP}" --cluster-name "${ARCNAME}" --cluster-type connectedClusters --name "acsa-`mktemp -u XXXXXX`" --extension-type microsoft.arc.containerstorage --config feature.diskStorageClass="default,local-path" --config  edgeStorageConfiguration.create=true
```

### Assign role to storage account

```bash
export pid=`az k8s-extension list --cluster-name "${ARCNAME}" --resource-group "${RESOURCE_GROUP}" --cluster-type connectedClusters | jq --arg extType "microsoft.arc.containerstorage" 'map(select(.extensionType == $extType)) | .[] | .identity.principalId' -r`
az role assignment create --assignee $pid --role "Storage Blob Data Owner" --scope "/subscriptions/${SUBSCRIPTION}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGEACCOUNT}"
```

### Configure ACSA with an SFTP Front End

For this example, all the necessary components were packaged in deployment.yaml; this includes the PVC creation, the Ingest Subvolume config, and the SFTP setup. Make any necessary changes to deployment.yaml before running it. For more information about the cloud connected storage account setting, see [here](https://learn.microsoft.com/azure/azure-arc/container-storage/cloud-ingest-edge-volume-configuration?tabs=portal#attach-subvolume-to-edge-volume).

```bash
kubectl apply -f deployment.yaml
```

### Start writing files to your SFTP Server

1. Let's create a sample file to push through to make sure our server setup is working.
   
 ```bash
 echo "Hello World! I'm so glad my SFTP front end is working with ACSA!" > testfile1.txt
 ```

2. Run the following command to get the IP address of your SFTP server, and note it for the next step:
   
 ```bash
 kubectl get service
 ```

3. Next, we will run the SFTP command. For our example, the user and password are both 'demo,' but you will want to change those to be something meaningful and secure.
   
 ```bash
 sftp demo@IPADDRESS
 ```

You'll have to enter your password here.

4. **From here, you'll need to change directories to the location you specified. In this example, it's /acsa/exampleSubDir.**
   
 ```bash
 cd /acsa/exampleSubDir
 ```

5. Then, we can put our file using:
   
 ```bash
 put testfile1.txt
 ```

### Confirm your file is uploaded

Finally, we can go to the Azure Portal and check our specified storage account container in our specified storage account. Our testfile1.txt should be there.
Note: Please keep in mind that we have set up this system with the default Ingest Policy, which waits 5 minutes after a file is written before it will upload it to the cloud. So if you don't see your file right away, just wait a few minutes. Policies can also be altered according to [these instructions](https://learn.microsoft.com/azure/azure-arc/container-storage/cloud-ingest-edge-volume-configuration?tabs=portal#optional-modify-the-ingestpolicy-from-the-default).