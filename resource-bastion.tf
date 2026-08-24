locals {
  bastion_friendly_name = "Azure Bastion"
  bastion_name          = "ba-${var.prefix}"
  bastion_name_location = lower("${local.bastion_name}-${lower(var.location)}")
  bastion_random_suffix = substr(md5(local.bastion_name_location), 0, 6)
  bastion_name_hostname = lower(substr(replace("c${local.bastion_random_suffix}${local.bastion_name_location}", "-", ""), 0, 24))
  subnet_bastion = {
    address_format_ipv4 = "10.%s.2.0/23"
    service_endpoints   = null
    delegation          = null
  }
}

## The subnet must be in the same VNet and resource group as the bastion host.

## Bastion costs $$$ (unless it is Developer - which is free) - around $100 per month per region! (this code will create one bastion per region!!!)
## Bastion is a managed service - no need to patch or update
resource "azurerm_public_ip" "bastion" {
  for_each = { for k, v in azurerm_virtual_network.this : k => v if var.bastion_sku != "Developer" }

  name                = "pip-${local.bastion_name_location}"
  resource_group_name = module.environment_resource_group.resource.name
  location            = azurerm_resource_group.environment.location
  allocation_method   = "Static"
  sku                 = "Standard"
  sku_tier            = "Regional"
  domain_name_label   = local.bastion_name_hostname
  tags                = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

/*
resource "azurerm_monitor_diagnostic_setting" "bastion-publicip1" {
  for_each = { for k, v in azurerm_public_ip.bastion : k => v if var.bastion_sku != "Developer" }

  name                       = "Audit-${each.value.name}-to-Azure-Monitor"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "audit"
  }
}
*/

/*
resource "azurerm_monitor_diagnostic_setting" "bastion-publicip2" {
  for_each = { for k, v in azurerm_public_ip.bastion : k => v if var.bastion_sku != "Developer" }

  name                       = "Logs-${each.value.name}-to-Azure-Monitor"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
}
*/

resource "azurerm_subnet" "bastion" {
  for_each = { for k, v in azurerm_virtual_network.this : k => v if var.bastion_sku != "Developer" }

  name                            = "AzureBastionSubnet"
  resource_group_name             = module.environment_resource_group.resource.name
  virtual_network_name            = each.value.name
  address_prefixes                = [format(local.subnet_bastion.address_format_ipv4, local.regions[each.key].location_number)]
  default_outbound_access_enabled = false

  service_endpoints                             = []
  private_link_service_network_policies_enabled = false
  ## Supported values: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled.
  ## Keep this as Enabled so private endpoint network policies remain active on this subnet unless a workload explicitly requires policy exemptions.
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_bastion_host" "this" {
  name                = local.bastion_name_location
  resource_group_name = module.environment_resource_group.resource.name
  location            = azurerm_resource_group.environment.location

  dynamic "ip_configuration" {
    for_each = var.bastion_sku != "Developer" ? [1] : []

    content {
      name                 = lower("${local.bastion_name}-config")
      subnet_id            = azurerm_subnet.bastion.id
      public_ip_address_id = azurerm_public_ip.bastion.id
    }
  }
  ## AZs are free with Bastion
  zones = var.bastion_sku != "Developer" ? local.regions[var.location].zones : []

  ## Basic is the other option
  sku                = var.bastion_sku
  copy_paste_enabled = true

  ## Standard SKU features
  file_copy_enabled = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? true : false
  tunneling_enabled = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? true : false
  ## Tunnel can be used to access a Windows VM - Windows Admin Center (WAC)

  scale_units            = 2
  ip_connect_enabled     = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? true : false
  kerberos_enabled       = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? true : false
  shareable_link_enabled = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? true : false

  ## Premium Only features
  session_recording_enabled = var.bastion_sku == "Premium" ? true : false

  virtual_network_id = azurerm_virtual_network.this.id

  timeouts {
    create = "90m"
  }

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

output "bastion_id" {
  description = "Bastion Host ID"
  value       = azurerm_bastion_host.this.id
  sensitive   = false
}

output "bastion_command_wac_tunnel_pwsh" {
  description = "Bastion Tunnel command to access Windows Admin Center - only works with Standard or Premium Bastion SKUs"
  sensitive   = false
  value       = "Start-BastionTunnel -VmName 'vm-name' -BastionName '${azurerm_bastion_host.this.name}' -BastionResourceGroup '${azurerm_bastion_host.this.resource_group_name}' -ResourcePort 6516 -LocalPort 8443"
  ## Then browse to https://localhost:8443 and log in with your Azure credentials. This will open a secure tunnel to the target VM over HTTPS. You can also use this command to connect to a Windows VM using Windows Admin Center (WAC) if the WAC extension is installed on the target VM.
}

output "bastion_command_native_rdp" {
  description = "Bastion RDP command to access a Windows VM (via native client) - only works with Standard or Premium Bastion SKUs"
  sensitive   = false
  ## Remote RDP connections to VMs that are joined to Microsoft Entra ID is allowed only from Windows 10 or later PCs that are either Microsoft Entra registered, Microsoft Entra joined, or Microsoft Entra hybrid joined to the same directory as the VM.
  value = "az network bastion rdp --name ${azurerm_bastion_host.this.name} --resource-group ${azurerm_bastion_host.this.resource_group_name} --target-resource-id <vm-name>"
}



output "bastion_command_native_ssh" {
  description = "Bastion SSH command to access a Linux VM (via native client) - only works with Standard or Premium Bastion SKUs"
  sensitive   = false
  ## Remote SSH connections to VMs that are joined to Microsoft Entra ID is allowed only from Windows 10 or later PCs that are either Microsoft Entra registered, Microsoft Entra joined, or Microsoft Entra hybrid joined to the same directory as the VM.
  value = "az network bastion ssh --name ${azurerm_bastion_host.this.name} --resource-group ${azurerm_bastion_host.this.resource_group_name} --target-resource-id <vm-name>"
}

/*
resource "azurerm_monitor_diagnostic_setting" "bastion1" {
  name                       = "Audit-${azurerm_bastion_host.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_bastion_host.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "audit"
  }
}
resource "azurerm_monitor_diagnostic_setting" "bastion2" {
  name                       = "Logs-${azurerm_bastion_host.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_bastion_host.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
}
*/

resource "azurerm_network_security_group" "bastion" {
  for_each = { for k, v in azurerm_virtual_network.this : k => v if var.bastion_sku != "Developer" }

  name                = "nsg-bastion-${lower(azurerm_resource_group.environment.location)}"
  resource_group_name = module.environment_resource_group.resource.name
  location            = azurerm_resource_group.environment.location

  ### Ingress Traffic from public internet:
  ### The Azure Bastion will create a public IP that needs port 443 enabled on the public IP for ingress traffic.
  ### Port 3389/22 are NOT required to be opened on the AzureBastionSubnet.
  ### Note that the source can be either the Internet or a set of public IP addresses that you specify.
  security_rule {
    name                       = "Inbound-AllowHttps-from-Internet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
    description                = "Inbound AllowHttps from Internet"
  }

  ### Ingress Traffic from Azure Bastion control plane:
  ### For control plane connectivity, enable port 443 inbound from GatewayManager service tag.
  ### This enables the control plane, that is, Gateway Manager to be able to talk to Azure Bastion.
  security_rule {
    name                       = "Inbound-AllowHttps-from-GatewayManager"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
    description                = "Inbound AllowHttps from Bastion Control Plane (GatewayManager)"
  }

  ### Ingress Traffic from Azure Bastion data plane:
  ### For data plane communication between the underlying components of Azure Bastion,
  ### enable ports 8080, 5701 inbound from the VirtualNetwork service tag to the VirtualNetwork service tag.
  ### This enables the components of Azure Bastion to talk to each other.
  security_rule {
    name                       = "Inbound-Bastion-Vnet"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow Inbound Control Plane for Bastion"
  }
  ### Ingress Traffic from Azure Load Balancer:
  ### For health probes, enable port 443 inbound from the AzureLoadBalancer service tag.
  ### This enables Azure Load Balancer to detect connectivity
  security_rule {
    name                       = "Inbound-AllowHttps-from-AzureLoadBalancer"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
    description                = "Allow Inbound Https from Azure Load Balancer (for Bastion)"
  }

  security_rule {
    name                       = "Outbound-Bastion-Vnet"
    priority                   = 160
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow Outbound Bastian between VNets"
  }
  security_rule {
    name                       = "Outbound-https-Internet"
    priority                   = 170
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
    description                = "Allow Https outbound to Internet"
  }
  ## Ingress Traffic from Azure Bastion:
  ## Azure Bastion will reach to the target VM over private IP.
  ## RDP/SSH ports (ports 3389/22 respectively, or custom port values if you are using the custom 
  ## port feature as a part of Standard SKU) need to be opened on the target VM side
  ##  over private IP. As a best practice, you can add the Azure Bastion Subnet IP address
  ##  range in this rule to allow only Bastion to be able to open these ports on the target VMs 
  ## in your target VM subnet.
  security_rule {
    name                       = "Outbound-AllowSshRdpWAC-to-Vnet"
    priority                   = 180
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["22", "3389", "6516"]
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow SSH/RDP/WAC from Bastion to VNets"
  }

  ## Outbound: AzureCloud
  security_rule {
    name                       = "Allow-Azure"
    priority                   = 606
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
    description                = "Allow Azure Cloud"
  }

  ## Outbound: Deny All
  security_rule {
    name                       = "Deny-Anything-Else-Inbound"
    priority                   = 4095
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Deny ALL Inbound as part of Zero Trust Networking"
  }

  ## Inbound: Deny All
  security_rule {
    name                       = "Deny-Anything-Else-Outound"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny" ## needs to be "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Deny ALL Outbound as part of Zero Trust Networking"
  }

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

