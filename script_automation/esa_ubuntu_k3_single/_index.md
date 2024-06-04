# This example can be used to install ESA on an Ubuntu system with K3s. 

This example requires an Ubuntu machine or VM running K3s. We will Arc Connect the system through this example. 
You will need to create a storage account and provide your storage account name and container name in the below variables: 

```bash
export REGION="eastus"
export RESOURCE_GROUP="myResourceGroup"
export SUBSCRIPTION="your-subscription-id-here"
export ARCNAME="myArcClusterName" # will be used as displayname in portal
export STORAGEACCOUNT="myStorageAccountName"
export STORAGECONTAINER="nameOfContainerInStorageAccount"
```

## Arc Connect Kubernetes
```bash
az connectedk8s connect -n ${ARCNAME} -l ${REGION} -g ${RESOURCE_GROUP} --subscription ${SUBSCRIPTION}
```
## Install Open Service Mesh
```bash
az k8s-extension create --resource-group ${RESOURCE_GROUP} --cluster-name ${ARCNAME} --cluster-type connectedClusters --extension-type Microsoft.openservicemesh --scope cluster --name osm
```
## Install Edge Storage Accelerator
```bash
az k8s-extension create --resource-group "${RESOURCE_GROUP}" --cluster-name "${ARCNAME}" --cluster-type connectedClusters --name esa --extension-type microsoft.edgestorageaccelerator --config-file config.json
```
## Configure ESA 
For this example, the components are separate and applied separately, however you can chose to combine them into a single yaml to reduce the number of config files you have to maintain. 

```bash
./get_storage_key.sh -g ${RESOURCE_GROUP} -s ${STORAGEACCOUNT} -n "default"
cat pv.template.yaml | sed "s/STORAGEACCOUNT/$STORAGEACCOUNT/g" | sed "s/STORAGECONTAINER/$STORAGECONTAINER/g" > pv.yaml
kubectl apply -f pv.yaml
kubectl apply -f pvc.yaml
kubectl apply -f examplepod.yaml
```

## Attach to example pod to use /mnt/esa

```bash
example_pod=`kubectl get pod -o yaml | grep name | head -1 | awk -F ':' '{print $2}'`
kubectl exec -it ${example_pod} -- bash
```

For help, visit https://learn.microsoft.com/en-us/azure/azure-arc/edge-storage-accelerator
