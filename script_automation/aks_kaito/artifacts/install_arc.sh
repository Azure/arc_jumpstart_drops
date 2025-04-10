#!/bin/bash
export clusterName="JumpstartAKS"
export resourceGroupName="Jumpstart-Kaito"

# Login to Azure and get kubeconfig for the AKS cluster
az login
az aks get-credentials --name $clusterName --resource-group $resourceGroupName --overwrite-existing

# Arc-enable the cluster
az connectedk8s connect -n kaito-aksarc -g $resourceGroupName

# Connect to the Arc-enabled cluster via connectedk8s extension
kubectl create serviceaccount arc-user -n default
kubectl create clusterrolebinding arc-user-binding --clusterrole cluster-admin --serviceaccount default:arc-user
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: arc-user-secret
  annotations:
    kubernetes.io/service-account.name: arc-user
type: kubernetes.io/service-account-token
EOF
TOKEN=$(kubectl get secret arc-user-secret -o jsonpath='{$.data.token}' | base64 -d | sed 's/$/\n/g')

# From another shell window, use cluster connect setup a port forward to the AKS cluster
az connectedk8s proxy -n kaito-aksarc -g $resourceGroupName --token $TOKEN
