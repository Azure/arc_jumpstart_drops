#!/bin/env bash

### Install K3s  
curl -sfL https://get.k3s.io | sh -

### K3s environment settings
mkdir ~/.kube
sudo KUBECONFIG=~/.kube/config:/etc/rancher/k3s/k3s.yaml kubectl config view --flatten > ~/.kube/merged
mv ~/.kube/merged ~/.kube/config
chmod  0600 ~/.kube/config
export KUBECONFIG=~/.kube/config
#switch to k3s context
kubectl config use-context default
echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc

### Install AZ Cli
curl -L https://aka.ms/InstallAzureCli | bash
exec -l $SHELL
sudo apt install unzip
