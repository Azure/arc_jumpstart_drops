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
echo $keyVaultName:$7| awk '{print substr($1,2); }' >> vars.sh
echo $keyVaultSecretName:$8 | awk '{print substr($1,2); }' >> vars.sh
echo $azureTenantId:$9 | awk '{print substr($1,2); }' >> vars.sh
echo $userAssignedIdentityName:${10} | awk '{print substr($1,2); }' >> vars.sh
echo $kubernetesNamespace:${11} | awk '{print substr($1,2); }' >> vars.sh
echo $serviceAccountName:${12} | awk '{print substr($1,2); }' >> vars.sh
echo $federatedCredentialIdentityName:${13} | awk '{print substr($1,2); }' >> vars.sh
echo $certManagerVersion:${14} | awk '{print substr($1,2); }' >> vars.sh

sed -i '2s/^/export adminUsername=/' vars.sh
sed -i '3s/^/export subscriptionId=/' vars.sh
sed -i '4s/^/export vmName=/' vars.sh
sed -i '5s/^/export location=/' vars.sh
sed -i '6s/^/export templateBaseUrl=/' vars.sh
sed -i '7s/^/export resourceGroup=/' vars.sh
sed -i '8s/^/export keyVaultName=/' vars.sh
sed -i '9s/^/export keyVaultSecretName=/' vars.sh
sed -i '10s/^/export azureTenantId=/' vars.sh
sed -i '11s/^/export userAssignedIdentityName=/' vars.sh
sed -i '12s/^/export kubernetesNamespace=/' vars.sh
sed -i '13s/^/export serviceAccountName=/' vars.sh
sed -i '14s/^/export federatedCredentialIdentityName=/' vars.sh
sed -i '15s/^/export certManagerVersion=/' vars.sh

export vmName=$3

# Save the original stdout and stderr
exec 3>&1 4>&2

exec >k3sWithSSE-${vmName}.log
exec 2>&1

# Set k3 deployment variables
export K3S_VERSION="1.29.6+k3s2" # Do not change!

chmod +x vars.sh
. ./vars.sh

# Creating login message of the day (motd)
sudo curl -v -o /etc/profile.d/welcomeK3s.sh ${templateBaseUrl}scritps/welcomeK3s.sh

# Syncing this script log to 'jumpstart_logs' directory for ease of troubleshooting
sudo -u $adminUsername mkdir -p /home/${adminUsername}/jumpstart_logs
while sleep 1; do sudo -s rsync -a /var/lib/waagent/custom-script/download/0/k3sWithSSE-$vmName.log /home/${adminUsername}/jumpstart_logs/k3sWithSSE-$vmName.log; done &

# Function to check if dpkg lock is in place
check_dpkg_lock() {
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo "Waiting for other package management processes to complete..."
        sleep 5
    done
}
# Run the lock check before attempting the installation
check_dpkg_lock

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

# Function to check if an extension is already installed
is_extension_installed() {
    extension_name=$1
    extension_count=$(sudo -u $adminUsername az k8s-extension list --cluster-name $vmName --resource-group $resourceGroup --cluster-type connectedClusters --query "[?name=='$extension_name'] | length(@)")

    if [ "$extension_count" -gt 0 ]; then
        return 0 # Extension is installed
    else
        return 1 # Extension is not installed
    fi
}
serviceAccountIssuer=$(sudo -u $adminUsername az connectedk8s show --name $vmName --resource-group $resourceGroup --query "oidcIssuerProfile.issuerUrl" --output tsv)
echo ""
echo "OIDC issuer URL: $serviceAccountIssuer"
echo ""

# sudo vim /etc/systemd/system/k3s.service

# ExecStart=/usr/local/bin/k3s \
#   server --write-kubeconfig-mode=644 \
    #  '--kube-apiserver-arg=--service-account-issuer=https://oidcdiscovery-northamerica-endpoint-gbcge4adgqebgxev.z01.azurefd.net/2ffc1db7-b373-4be0-a5ec-f54edd5bf695/84daf1c1-8694-406d-9ca3-fd9f423ac1e3/' \
    #  '--kube-apiserver-arg=--enable-admission-plugins=OwnerReferencesPermissionEnforcement' \
# sed -i "$ a\ '--kube-apiserver-arg=--service-account-issuer=${serviceAccountIssuer}' \\\/" service

# Ensure the last line is empty and delete it if it is
sed -i '${/^$/d}' /etc/systemd/system/k3s.service

# Append the required flags to the k3s.service file
sudo sed -i '$ a\ '\''--kube-apiserver-arg=--enable-admission-plugins=OwnerReferencesPermissionEnforcement'\'' \\' /etc/systemd/system/k3s.service
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to append enable-admission-plugins to k3s.service"
    exit 1
fi

sudo sed -i "$ a\ '--kube-apiserver-arg=--service-account-issuer=${serviceAccountIssuer}'" /etc/systemd/system/k3s.service
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to append service-account-issuer to k3s.service"
    exit 1
fi

sudo systemctl daemon-reload
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to reload systemd daemon"
    exit 1
fi

sudo systemctl restart k3s
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to restart k3s service"
    exit 1
fi

max_retries=5
retry_count=0
success=false

while [ $retry_count -lt $max_retries ]; do
    sudo -u $adminUsername az keyvault secret set --vault-name $keyVaultName --name $keyVaultSecretName --value 'JumpstartDrops!'
    if [ $? -eq 0 ]; then
        success=true
        break
    else
        echo "Failed to set secret in Key Vault. Retrying (Attempt $((retry_count+1)))..."
        retry_count=$((retry_count+1))
        sleep 10
    fi
done

if [ "$success" = false ]; then
    echo "Error: Failed to set secret in Key Vault after $max_retries attempts."
    exit 1
fi

# Create a federated identity credential
cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Namespace
    metadata:
        name: $kubernetesNamespace
EOF

cat <<EOF | kubectl apply -f -
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: $serviceAccountName
    namespace: $kubernetesNamespace
EOF

userAssignedClientId=$(sudo -u $adminUsername az identity show --resource-group $resourceGroup --name $userAssignedIdentityName --query 'clientId' -otsv)

sudo -u $adminUsername az identity federated-credential create --name $federatedCredentialIdentityName --identity-name $userAssignedIdentityName --resource-group $resourceGroup --issuer $serviceAccountIssuer --subject system:serviceaccount:${kubernetesNamespace}:${serviceAccountName}
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create federated credential"
    exit 1
fi

#
# Install the Secret Store Extension for Kubernetes
#

helm repo add jetstack https://charts.jetstack.io/ --force-update
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to add jetstack helm repo"
    exit 1
fi

helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version $certManagerVersion --set crds.enabled=true
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to install cert-manager"
    exit 1
fi

helm upgrade trust-manager jetstack/trust-manager --install --namespace cert-manager --wait
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to upgrade/install trust-manager"
    exit 1
fi

# Enabling Secret Store Extension for Kubernetes on the cluster
echo ""
echo "Enabling Secret Store Extension for Kubernetes on the cluster"
echo ""

# Check and install Secret Store Extension extension
if is_extension_installed "ssarcextension "; then
    echo "Extension 'ssarcextension' is already installed."
else
    echo "Extension 'ssarcextension' is not installed -  triggering installation"
    sudo -u $adminUsername az k8s-extension create --cluster-name $vmName --cluster-type connectedClusters --extension-type microsoft.azure.secretstore --resource-group $resourceGroup --release-train preview --name ssarcextension --scope cluster
fi

###
### Configure the SSE
###

# Create a SecretProviderClass resource
kubectl apply -f - <<EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: secret-provider-class-name                      # Name of the class; must be unique per Kubernetes namespace
  namespace: ${kubernetesNamespace}                    # Kubernetes namespace to make the secrets accessible in
spec:
  provider: azure
  parameters:
    clientID: "${userAssignedClientId}"               # Managed Identity Client ID for accessing the Azure Key Vault with.
    keyvaultName: ${keyVaultName}                       # The name of the Azure Key Vault to synchronize secrets from.
    objects: |
      array:
        - |
          objectName: ${keyVaultSecretName}            # The name of the secret to sychronize.
          objectType: secret
          objectVersionHistory: 2                       # [optional] The number of versions to synchronize, starting from latest.
    tenantID: "${azureTenantId}"                       # The tenant ID of the Key Vault 
EOF

# Create a SecretSync object
kubectl apply -f - <<EOF
apiVersion: secret-sync.x-k8s.io/v1alpha1
kind: SecretSync
metadata:
  name: secret-sync-name                                  # Name of the object; must be unique per Kubernetes namespace
  namespace: ${kubernetesNamespace}                      # Kubernetes namespace
spec:
  serviceAccountName: ${serviceAccountName}             # The Kubernetes service account to be given permissions to access the secret.
  secretProviderClassName: secret-provider-class-name     # The name of the matching SecretProviderClass with the configuration to access the AKV storing this secret
  secretObject:
    type: Opaque
    data:
    - sourcePath: ${keyVaultSecretName}/0                # Name of the secret in Azure Key Vault with an optional version number (defaults to latest)
      targetKey: ${keyVaultSecretName}-data-key0         # Target name of the secret in the Kubernetes secret store (must be unique)
EOF

exit 0
