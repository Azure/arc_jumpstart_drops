#!/bin/bash
sudo apt-get update

sudo sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
sudo adduser staginguser --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password
sudo echo "staginguser:ArcPassw0rd" | sudo chpasswd

# Injecting environment variables
echo '#!/bin/bash' >> vars.sh
echo $adminUsername:$1 | awk '{print substr($1,2); }' >> vars.sh
echo $subscriptionId:$2 | awk '{print substr($1,2); }' >> vars.sh
echo $vmName:$3 | awk '{print substr($1,2); }' >> vars.sh
echo $location:$4 | awk '{print substr($1,2); }' >> vars.sh
echo $templateBaseUrl:$5 | awk '{print substr($1,2); }' >> vars.sh
echo $resourceGroup:$6| awk '{print substr($1,2); }' >> vars.sh
echo $monitorWorkspaceId:$7| awk '{print substr($1,2); }' >> vars.sh
# echo $kubernetesNamespace:$8 | awk '{print substr($1,2); }' >> vars.sh
# echo $azureTenantId:$9 | awk '{print substr($1,2); }' >> vars.sh
# echo $userAssignedIdentityName:${10} | awk '{print substr($1,2); }' >> vars.sh
# echo $kubernetesNamespace:${11} | awk '{print substr($1,2); }' >> vars.sh
# echo $serviceAccountName:${12} | awk '{print substr($1,2); }' >> vars.sh
# echo $federatedCredentialIdentityName:${13} | awk '{print substr($1,2); }' >> vars.sh
# echo $certManagerVersion:${14} | awk '{print substr($1,2); }' >> vars.sh

sed -i '2s/^/export adminUsername=/' vars.sh
sed -i '3s/^/export subscriptionId=/' vars.sh
sed -i '4s/^/export vmName=/' vars.sh
sed -i '5s/^/export location=/' vars.sh
sed -i '6s/^/export templateBaseUrl=/' vars.sh
sed -i '7s/^/export resourceGroup=/' vars.sh
sed -i '8s/^/export monitorWorkspaceId=/' vars.sh
# sed -i '9s/^/export kubernetesNamespace=/' vars.sh
# sed -i '10s/^/export azureTenantId=/' vars.sh
# sed -i '11s/^/export userAssignedIdentityName=/' vars.sh
# sed -i '12s/^/export kubernetesNamespace=/' vars.sh
# sed -i '13s/^/export serviceAccountName=/' vars.sh
# sed -i '14s/^/export federatedCredentialIdentityName=/' vars.sh
# sed -i '15s/^/export certManagerVersion=/' vars.sh

export vmName=$3

# Save the original stdout and stderr
exec 3>&1 4>&2

exec >k3sMonitoring-${vmName}.log
exec 2>&1

# Set k3 deployment variables
export K3S_VERSION="1.32.0+k3s1" # Do not change!

chmod +x vars.sh
. ./vars.sh

# Creating login message of the day (motd)
curl -v -o /etc/profile.d/welcomeK3s.sh ${templateBaseUrl}scripts/welcomeK3s.sh

# Syncing this script log to 'jumpstart_logs' directory for ease of troubleshooting
sudo -u $adminUsername mkdir -p /home/${adminUsername}/jumpstart_logs
while sleep 1; do sudo -s rsync -a /var/lib/waagent/custom-script/download/0/k3sMonitoring-$vmName.log /home/${adminUsername}/jumpstart_logs/k3sMonitoring-$vmName.log; done &

# Function to check if dpkg lock is in place
check_dpkg_lock() {
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo "Waiting for other package management processes to complete..."
        sleep 5
    done
}
# Run the lock check before attempting the installation
check_dpkg_lock

# Installing Azure CLI & Azure Arc extensions
max_retries=5
retry_count=0
success=false

while [ $retry_count -lt $max_retries ]; do
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    if [ $? -eq 0 ]; then
        success=true
        break
    else
        echo "Failed to install Az CLI. Retrying (Attempt $((retry_count+1)))..."
        retry_count=$((retry_count+1))
        sleep 10
    fi
done

echo ""
echo "Log in to Azure"
echo ""
for i in {1..5}; do
    sudo -u $adminUsername az login --identity
    if [[ $? -eq 0 ]]; then
        break
    fi
    sleep 15
    if [[ $i -eq 5 ]]; then
        echo "Error: Failed to login to Azure after 5 retries"
        exit 1
    fi
done

sudo -u $adminUsername az account set --subscription $subscriptionId
az -v

check_dpkg_lock

# Installing Azure Arc extensions
echo ""
echo "Installing Azure Arc extensions"
echo ""
sudo -u $adminUsername az extension add --name connectedk8s
sudo -u $adminUsername az extension add --name k8s-configuration
sudo -u $adminUsername az extension add --name k8s-extension

# Installing Rancher K3s cluster (single control plane)
echo ""
echo "Installing Rancher K3s cluster"
echo ""
publicIp=$(hostname -i)
sudo mkdir ~/.kube
sudo -u $adminUsername mkdir /home/${adminUsername}/.kube
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --disable servicelb --node-ip ${publicIp} --node-external-ip ${publicIp} --bind-address ${publicIp} --tls-san ${publicIp}" INSTALL_K3S_VERSION=v${K3S_VERSION} K3S_KUBECONFIG_MODE="644" sh -
if [[ $? -ne 0 ]]; then
    echo "ERROR: K3s installation failed"
    exit 1
fi
# Renaming default context to k3s cluster name
context=$(echo $vmName | sed 's/-[^-]*$//')
sudo kubectl config rename-context default $context --kubeconfig /etc/rancher/k3s/k3s.yaml
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo cp /etc/rancher/k3s/k3s.yaml /home/${adminUsername}/.kube/config
sudo cp /etc/rancher/k3s/k3s.yaml /home/${adminUsername}/.kube/config.staging
sudo chown -R $adminUsername /home/${adminUsername}/.kube/
sudo chown -R staginguser /home/${adminUsername}/.kube/config.staging

# Installing Helm 3
echo ""
echo "Installing Helm"
echo ""
sudo snap install helm --classic
if [[ $? -ne 0 ]]; then
    echo "ERROR: Helm installation failed"
    exit 1
fi

echo ""
echo "Making sure Rancher K3s cluster is ready..."
echo ""
sudo kubectl wait --for=condition=Available --timeout=60s --all deployments -A >/dev/null
sudo kubectl get nodes -o wide | expand | awk 'length($0) > length(longest) { longest = $0 } { lines[NR] = $0 } END { gsub(/./, "=", longest); print "/=" longest "=\\"; n = length(longest); for(i = 1; i <= NR; ++i) { printf("| %s %*s\n", lines[i], n - length(lines[i]) + 1, "|"); } print "\\=" longest "=/" }'

# Onboard the cluster to Azure Arc
echo ""
echo "Onboarding the cluster to Azure Arc"
echo ""

max_retries=5
retry_count=0
success=false

while [ $retry_count -lt $max_retries ]; do
    sudo -u $adminUsername az connectedk8s connect --name $vmName --resource-group $resourceGroup --location $location --enable-oidc-issuer
    if [ $? -eq 0 ]; then
        success=true
        break
    else
        echo "Failed to onboard cluster to Azure Arc. Retrying (Attempt $((retry_count+1)))..."
        retry_count=$((retry_count+1))
        sleep 10
    fi
done

if [ "$success" = false ]; then
    echo "Error: Failed to onboard the cluster to Azure Arc after $max_retries attempts."
    exit 1
fi

echo ""
echo "Onboarding the k3s cluster to Azure Arc completed"
echo ""

# Verify if cluster is connected to Azure Arc successfully
connectedClusterInfo=$(sudo -u $adminUsername az connectedk8s show --name $vmName --resource-group $resourceGroup)
echo "Connected cluster info: $connectedClusterInfo"

# Enabling Secret Store Extension for Kubernetes on the cluster
echo ""
echo "Enable monitoring for Kubernetes clusters"
echo ""

# Set the Azure CLI to allow preview extensions
az config set extension.dynamic_install_allow_preview=true 

# Create the Azure Monitor Metrics extension
max_retries=5
retry_count=0
success=false

while [ $retry_count -lt $max_retries ]; do
    sudo -u $adminUsername az k8s-extension create --name azuremonitor-metrics --cluster-name $vmName --resource-group $resourceGroup --cluster-type connectedClusters --extension-type Microsoft.AzureMonitor.Containers.Metrics --configuration-settings azure-monitor-workspace-resource-id=$monitorWorkspaceId --verbose
    if [ $? -eq 0 ]; then
        success=true
        break
    else
        echo "Failed to enable Azure Monitor Metrics extension. Retrying (Attempt $((retry_count+1)))..."
        retry_count=$((retry_count+1))
        sleep 10
    fi
done

if [ "$success" = false ]; then
    echo "Error: Failed to enable Azure Monitor Metrics extension after $max_retries attempts."
    exit 1
fi

exit 0
