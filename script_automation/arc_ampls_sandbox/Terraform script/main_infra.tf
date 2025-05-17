terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.28.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 1.10.0"
    }
        azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.0.0"
    }
  }
}


provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
provider "azuread" {
  tenant_id       = var.tenant_id
}


provider "azapi" {}



resource "azurerm_resource_group" "onprem" {
  name     = "Arc-OnPrem-RG"
  location = "francecentral"
}

resource "azurerm_resource_group" "azure" {
  name     = "Arc-Azure-RG"
  location = "francecentral"
}


resource "azurerm_virtual_network" "main_vnet" {
  name                = "arc-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name
}

resource "azurerm_subnet" "main_subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.onprem.name
  virtual_network_name = azurerm_virtual_network.main_vnet.name
  address_prefixes     = ["10.10.1.0/24"]
  
}
resource "azurerm_virtual_network" "azure_vnet" {
  name                = "arc-azure-vnet"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.azure.location
  resource_group_name = azurerm_resource_group.azure.name
}

resource "azurerm_subnet" "azure_subnet" {
  name                 = "azure-subnet"
  resource_group_name  = azurerm_resource_group.azure.name
  virtual_network_name = azurerm_virtual_network.azure_vnet.name
  address_prefixes     = ["10.20.1.0/24"]
}
resource "azurerm_subnet" "cloud_gateway_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.azure.name
  virtual_network_name = azurerm_virtual_network.azure_vnet.name
  address_prefixes     = ["10.20.0.0/26"]
}
resource "azurerm_subnet" "onprem_gateway_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.onprem.name
  virtual_network_name = azurerm_virtual_network.main_vnet.name
  address_prefixes     = ["10.10.3.0/26"]
}

resource "azurerm_public_ip" "onprem_gw_ip" {
  name                = "OnPremGateway-PIP"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "azure_gw_ip" {
  name                = "AzureGateway-PIP"
  location            = azurerm_resource_group.azure.location
  resource_group_name = azurerm_resource_group.azure.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_virtual_network_gateway" "onprem_gw" {
  name                = "OnPremGateway"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name

  type     = "Vpn"
  vpn_type = "RouteBased"
  enable_bgp = false
  sku      = "VpnGw1"

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.onprem_gw_ip.id
    subnet_id = azurerm_subnet.onprem_gateway_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
    lifecycle {
    create_before_destroy = true
    prevent_destroy = false
  }
}
resource "azurerm_virtual_network_gateway" "azure_gw" {
  name                = "AzureGateway"
  location            = azurerm_resource_group.azure.location
  resource_group_name = azurerm_resource_group.azure.name

  type     = "Vpn"
  vpn_type = "RouteBased"
  enable_bgp = false
  sku      = "VpnGw1"

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.azure_gw_ip.id
    subnet_id                     = azurerm_subnet.cloud_gateway_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_virtual_network_gateway_connection" "azure_to_onprem" {
  name                            = "azure-to-onprem"
  location                        = azurerm_resource_group.azure.location
  resource_group_name             = azurerm_resource_group.azure.name
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.azure_gw.id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.onprem_gw.id
  type                            = "Vnet2Vnet"
  shared_key                      = "ArcPa$$w0rd"
}

resource "azurerm_virtual_network_gateway_connection" "onprem_to_azure" {
  name                            = "onprem-to-azure"
  location                        = azurerm_resource_group.onprem.location
  resource_group_name             = azurerm_resource_group.onprem.name
  virtual_network_gateway_id      = azurerm_virtual_network_gateway.onprem_gw.id
  peer_virtual_network_gateway_id = azurerm_virtual_network_gateway.azure_gw.id
  type                            = "Vnet2Vnet"
  shared_key                      = "ArcPa$$w0rd"
}


resource "azapi_resource" "arc_private_link_scope" {
  type      = "Microsoft.HybridCompute/privateLinkScopes@2022-12-27"
  name      = "Arc-HIS-Scope"
  location  = azurerm_resource_group.onprem.location
  parent_id = azurerm_resource_group.azure.id

  schema_validation_enabled = false

  body = jsonencode({
    properties = {
      publicNetworkAccess = "Disabled"
    }
  })
}

resource "azurerm_private_endpoint" "arc_pe" {
  name                = "Arc-PE"
  location            = azurerm_resource_group.azure.location
  resource_group_name = azurerm_resource_group.azure.name
  subnet_id           = azurerm_subnet.azure_subnet.id

  private_service_connection {
    name                           = "ArcPrivateConnection"
    private_connection_resource_id = azapi_resource.arc_private_link_scope.id
    subresource_names              = ["hybridCompute"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
   name                 = "default"
   private_dns_zone_ids = [
    azurerm_private_dns_zone.his.id,
    azurerm_private_dns_zone.guestconfig.id,
     azurerm_private_dns_zone.kubeconfig.id
    ]
  }
}


resource "azurerm_network_interface" "main_nic" {
  name                = "arc-vm-nic"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}


resource "azurerm_public_ip" "bastion_ip" {
  name                = "arc-bastion-pip"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_subnet" "bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.onprem.name
  virtual_network_name = azurerm_virtual_network.main_vnet.name
  address_prefixes     = ["10.10.2.0/27"]
}

resource "azurerm_bastion_host" "main" {
  name                = "arc-bastion"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name

  sku = "Standard"

  ip_configuration {
    name                 = "bastionConfig"
    subnet_id            = azurerm_subnet.bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.bastion_ip.id

  }
}


resource "azurerm_private_dns_zone" "guestconfig" {
  name                = "privatelink.guestconfiguration.azure.com"
  resource_group_name = azurerm_resource_group.azure.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "guestconfig_link" {
  name                  = "guestconfig-link"
 resource_group_name   = azurerm_private_dns_zone.guestconfig.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.guestconfig.name
  virtual_network_id    = azurerm_virtual_network.main_vnet.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone" "kubeconfig" {
  name                = "privatelink.dp.kubernetesconfiguration.azure.com"
  resource_group_name = azurerm_resource_group.azure.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "kubeconfig_link" {
  name                  = "kubeconfig-link"
  resource_group_name   = azurerm_private_dns_zone.kubeconfig.resource_group_name
 private_dns_zone_name = azurerm_private_dns_zone.kubeconfig.name
  virtual_network_id    = azurerm_virtual_network.main_vnet.id
  registration_enabled  = false
}

resource "azurerm_private_dns_zone" "his" {
  name                = "privatelink.his.arc.azure.com"
  resource_group_name = azurerm_resource_group.azure.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "his_link" {
 name                  = "his-link"
 resource_group_name   = azurerm_private_dns_zone.his.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.his.name
  virtual_network_id    = azurerm_virtual_network.main_vnet.id
 registration_enabled  = false
}


resource "azurerm_network_security_group" "onprem_nsg" {
  name                = "onprem-vm-nsg"
  location            = azurerm_resource_group.onprem.location
  resource_group_name = azurerm_resource_group.onprem.name

  security_rule {
    name                       = "allow-rdp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-inbound-all"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "onprem_subnet_assoc" {
  subnet_id = azurerm_subnet.main_subnet.id
  network_security_group_id = azurerm_network_security_group.onprem_nsg.id
}

resource "azurerm_log_analytics_workspace" "default" {
  name                = "Arc-LogAnalytics"
  location            = azurerm_resource_group.azure.location
  resource_group_name = azurerm_resource_group.azure.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}



resource "azurerm_monitor_private_link_scope" "example" {
  name                = "arc-ampls"
  resource_group_name = azurerm_resource_group.azure.name

  ingestion_access_mode = "PrivateOnly"
  query_access_mode     = "Open"
}

resource "azurerm_private_endpoint" "ampls_pe" {
  name                = "ampls-pe"
  location            = azurerm_resource_group.azure.location
  resource_group_name = azurerm_resource_group.azure.name
  subnet_id           = azurerm_subnet.azure_subnet.id

  private_service_connection {
    name                           = "amplsPrivateConnection"
    private_connection_resource_id = azurerm_monitor_private_link_scope.example.id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.ampls_logs.id
    ]
  }
}
resource "azurerm_private_dns_zone" "ampls_logs" {
  name                = "privatelink.monitor.azure.com"
  resource_group_name = azurerm_resource_group.azure.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "ampls_logs_link" {
  name                  = "ampls-dns-link"
  resource_group_name   = azurerm_resource_group.azure.name
  private_dns_zone_name = azurerm_private_dns_zone.ampls_logs.name
  virtual_network_id    = azurerm_virtual_network.main_vnet.id
  registration_enabled  = false
}

resource "azurerm_monitor_data_collection_endpoint" "private_dce" {
  name                = "arc-private-dce"
  location            = azurerm_resource_group.azure.location
  resource_group_name = azurerm_resource_group.azure.name
  kind                = "Windows"
  public_network_access_enabled = false
}

resource "azurerm_monitor_data_collection_rule" "security_dcr" {
  name                        = "DCR-SecurityEvents"
  location                    = azurerm_resource_group.azure.location
  resource_group_name         = azurerm_resource_group.azure.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.private_dce.id
  depends_on = [
  azurerm_monitor_data_collection_endpoint.private_dce,
  azurerm_log_analytics_workspace.default,
  azurerm_virtual_network_gateway.azure_gw,
  azurerm_virtual_network_gateway.onprem_gw
  ]
  destinations {
    log_analytics {
      name                  = "logAnalyticsDestination"
      workspace_resource_id = azurerm_log_analytics_workspace.default.id
    }
  }

  data_sources {
    performance_counter {
      name                          = "example-datasource-perfcounter"
      streams                       = ["Microsoft-Perf", "Microsoft-InsightsMetrics"]
      sampling_frequency_in_seconds = 60
      counter_specifiers            = ["Processor(*)\\% Processor Time"]
    }
  windows_event_log {
     streams = ["Microsoft-Event"]
     x_path_queries = ["Application!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0 or Level=5)]]",
       "Security!*[System[(EventID=4624 or EventID=4625 or EventID=4688)]]",
     "System!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0 or Level=5)]]"]
     name = "eventLogsDataSource"
   }
  }
  

  data_flow {
    streams      = ["Microsoft-InsightsMetrics", "Microsoft-Perf"]
    destinations = ["logAnalyticsDestination"]
  }
  data_flow {
   streams      = ["Microsoft-Event"]
   destinations = ["logAnalyticsDestination"]
 }
}

data "azurerm_policy_definition" "windows_ama_install" {
  display_name = "Configure Windows Arc-enabled machines to run Azure Monitor Agent"
}

data "azurerm_policy_definition" "associate_dcr" {
  display_name = "Configure Windows Machines to be associated with a Data Collection Rule or a Data Collection Endpoint"
}
resource "azurerm_resource_group_policy_assignment" "enable_ama_windows" {
  name                 = "Enable-AMA-WindowsArc"
  resource_group_id    = azurerm_resource_group.azure.id
  policy_definition_id = data.azurerm_policy_definition.windows_ama_install.id

  identity {
    type = "SystemAssigned"
  }

  location = azurerm_resource_group.azure.location
  enforce  = true
}

resource "azurerm_resource_group_policy_assignment" "associate_dcr_windows" {
  name                 = "Associate-DCR-WindowsArc"
  resource_group_id    = azurerm_resource_group.azure.id
  policy_definition_id = data.azurerm_policy_definition.associate_dcr.id

  parameters = <<PARAMS
    {
      "dcrResourceId": {
        "value": "${azurerm_monitor_data_collection_rule.security_dcr.id}"
      }
    }
PARAMS

  identity {
    type = "SystemAssigned"
  }

  location = azurerm_resource_group.azure.location
  enforce  = true
}
resource "azurerm_role_assignment" "ama_role_assignment" {
  scope                = azurerm_resource_group.azure.id
  role_definition_name = "Azure Connected Machine Resource Administrator"
  principal_id         = azurerm_resource_group_policy_assignment.enable_ama_windows.identity[0].principal_id
}

resource "azurerm_role_assignment" "dcr_role_assignments" {
  for_each = toset([
    "Azure Connected Machine Resource Administrator",
    "Monitoring Contributor"
  ])

  scope                = azurerm_resource_group.azure.id
  role_definition_name = each.key
  principal_id         = azurerm_resource_group_policy_assignment.associate_dcr_windows.identity[0].principal_id
}

resource "azurerm_windows_virtual_machine" "arc_vm" {
  name                = "ArcDemo-VM"
  resource_group_name = azurerm_resource_group.onprem.name
  location            = azurerm_resource_group.onprem.location
  size                = "Standard_D2s_v3"
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [azurerm_network_interface.main_nic.id]

  os_disk {
    name                 = "arcvm-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "arc_script" {
  name                 = "OnboardToArc"
  virtual_machine_id   = azurerm_windows_virtual_machine.arc_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  auto_upgrade_minor_version = true

protected_settings = <<PROTECTED
{
  "fileUris": [
    "https://raw.githubusercontent.com/technicalandcloud/Azure_Arc_PrivateLink_AMPLS/refs/heads/main/privatelink/artifacts/Bootstrap.ps1"
  ],
  "commandToExecute": "powershell.exe -ExecutionPolicy Bypass -File Bootstrap.ps1 -appId ${var.client_id} -password ${var.client_secret} -tenantId ${var.tenant_id} -resourceGroup Arc-Azure-RG -subscriptionId ${var.subscription_id} -location francecentral -PLscope /subscriptions/${var.subscription_id}/resourceGroups/Arc-Azure-RG/providers/Microsoft.HybridCompute/privateLinkScopes/Arc-HIS-Scope -PEname Arc-PE -adminUsername ${var.admin_username}"
}
PROTECTED

}


