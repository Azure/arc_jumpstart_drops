#!/bin/env bash

### K3  
curl -sfL https://get.k3s.io | sh -

### AIO settings
mkdir ~/.kube
sudo KUBECONFIG=~/.kube/config:/etc/rancher/k3s/k3s.yaml kubectl config view --flatten > ~/.kube/merged
mv ~/.kube/merged ~/.kube/config
chmod  0600 ~/.kube/config
export KUBECONFIG=~/.kube/config
#switch to k3s context
kubectl config use-context default

echo fs.inotify.max_user_instances=8192 | sudo tee -a /etc/sysctl.conf
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf

sudo sysctl -p

echo fs.file-max = 100000 | sudo tee -a /etc/sysctl.conf

sudo sysctl -p

echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
### AZ Cli
curl -L https://aka.ms/InstallAzureCli | bash
exec -l $SHELL
sudo apt install unzip

