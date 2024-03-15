# Environment Variables

export SUBSCRIPTIONID=<Provide your subscription ID>
export APPID=<Provide your Service Principal App ID>
export PASSWORD=<Provide your service principal password>
export TENANTID=<Provide your Tenant ID>
export RG=<Provide your resource group name>
export LOCATION=<Provide the Azure Region>
export VMNAME=<Provide the Azure VM name>

## Configure Ubuntu to allow Azure Arc Connected Machine Agent Installation 

echo "Configuring walinux agent"
sudo service walinuxagent stop
sudo waagent -deprovision -force
sudo rm -rf /var/lib/waagent

echo "Configuring Firewall"

sudo ufw --force enable
sudo ufw deny out from any to 169.254.169.254
sudo ufw default allow incoming
sudo apt-get update

echo "Reconfiguring Hostname"

sudo hostname $VMNAME
sudo -E /bin/sh -c 'echo $VMNAME > /etc/hostname'

# Download the installation package
wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh

# Install the hybrid agent
sudo bash ~/install_linux_azcmagent.sh

# Run connect command
sudo azcmagent connect \
  --service-principal-id "${APPID}" \
  --service-principal-secret "${PASSWORD}" \
  --resource-group "${RG}" \
  --tenant-id "${TENANTID}" \
  --location "${LOCATION}" \
  --subscription-id "${SUBSCRIPTIONID}" \
  --tags "Project=jumpstart_azure_arc_servers" \
  --correlation-id "d009f5dd-dba8-4ac7-bac9-b54ef3a6671a"

