locals {
  bastion_friendly_name = "Azure Bastion"
  bastion_name          = "ba-${var.prefix}"
  bastion_name_location = lower("${local.bastion_name}-${lower(var.location)}")
  bastion_random_suffix = substr(random_string.environment.result, 0, 6)
  bastion_name_hostname = lower(substr(replace("b${local.bastion_random_suffix}${local.bastion_name_location}", "-", ""), 0, 24))
  subnet_bastion = {
    address_format_ipv4 = "10.%s.2.0/23"
    service_endpoints   = null
    delegation          = null
  }
  bastion_access_principal_ids = [
    var.owner_entra_object_id
  ]
}

resource "azurerm_role_definition" "bastion_connect" {
  name        = "Bastion VM Connect for the ${title(var.customer)} ${upper(var.prefix)} environment"
  scope       = module.environment_resource_group.resource.id
  description = "Minimum permissions to connect to VMs via Azure Bastion: read VM, NIC, and Bastion host."

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Network/networkInterfaces/read",
      "Microsoft.Network/bastionHosts/read",
      "Microsoft.Network/bastionHosts/action", # required to initiate connection sessions
    ]
    not_actions = []
  }
  assignable_scopes = [
    module.environment_resource_group.resource.id
  ]
}

resource "azurerm_role_assignment" "bastion_connect" {
  for_each           = toset(local.bastion_access_principal_ids)
  scope              = module.environment_resource_group.resource.id
  role_definition_id = azurerm_role_definition.bastion_connect.role_definition_resource_id
  principal_id       = each.value
}

resource "azurerm_network_security_group" "bastion" {
  name                = "nsg-bastion-${lower(module.environment_resource_group.resource.location)}"
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location

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
  lifecycle {
    create_before_destroy = true
  }
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
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

module "bastion_subnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm//modules/subnet"
  version = "~> 0.22, < 1.0"

  name             = "AzureBastionSubnet"
  parent_id        = module.virtual_network.resource_id
  address_prefixes = [format(local.subnet_bastion.address_format_ipv4, local.regions[var.location].location_number)]

  default_outbound_access_enabled               = false
  service_endpoints                             = null
  private_link_service_network_policies_enabled = false
  ## Supported values: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled.
  ## Keep this as Enabled so private endpoint network policies remain active on this subnet unless a workload explicitly requires policy exemptions.
  private_endpoint_network_policies = "Disabled"

  route_table = {
    id = null
  }
  nat_gateway = {
    id = null
  }
  network_security_group = {
    id = azurerm_network_security_group.bastion.id
  }
}

module "avm-res-network-bastionhost" {
  source           = "Azure/avm-res-network-bastionhost/azurerm"
  version          = "0.9.0"
  enable_telemetry = var.enable_telemetry

  name               = local.bastion_name
  location           = module.environment_resource_group.resource.location
  parent_id          = module.environment_resource_group.resource.id
  sku                = var.bastion_sku
  copy_paste_enabled = true

  ip_configuration = var.bastion_sku == "Developer" ? null : {
    name             = lower("${local.bastion_name}-config")
    create_public_ip = true
    subnet_id        = module.bastion_subnet.resource_id
  }
  ## zones are free, but only on anything not 'Developer'
  zones = var.bastion_sku == "Developer" ? [] : local.regions[var.location].zones

  ## Standard SKU features
  file_copy_enabled = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? true : false
  tunneling_enabled = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? true : false
  ## Tunnel can be used to access a Windows Admin Center (WAC) on Azure VMs

  scale_units            = var.bastion_sku == "Developer" ? null : 2
  ip_connect_enabled     = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? true : false
  kerberos_enabled       = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? true : false
  shareable_link_enabled = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? true : false

  ## Premium Only features
  session_recording_enabled = var.bastion_sku == "Premium" ? true : false

  virtual_network_id = module.virtual_network.resource_id
  diagnostic_settings = var.logging_enabled == false ? null : {
    diag_setting_1 = {
      name       = "Optional Logging 1"
      log_groups = ["allLogs"]
      metric     = ["AllMetrics"]
      #metric_categories              = ["SLI", "Requests"]
      log_analytics_destination_type = null
      workspace_resource_id          = module.log_analytics_workspace.resource.resource_id
    }
  }

  depends_on = [
    module.environment_resource_group,
    module.virtual_network
  ]
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

output "bastion_id" {
  description = "Bastion Host ID"
  sensitive   = false
  value       = module.avm-res-network-bastionhost.resource_id
}

output "bastion_command_wac_tunnel_pwsh" {
  description = "Bastion Tunnel command to access Windows Admin Center - only works with Standard or Premium Bastion SKUs"
  sensitive   = false
  value       = <<VEOF
## Bastion Tunnel command to access Windows Admin Center (WAC) - only works with Standard or Premium Bastion SKUs
Start-BastionTunnel -VmName 'vm-name' -BastionName '${module.avm-res-network-bastionhost.name}' -BastionResourceGroup '${module.environment_resource_group.resource.name}' -ResourcePort 6516 -LocalPort 8443
## Then browse to https://localhost:8443 and log in with your Azure credentials. This will open a secure tunnel to the target VM over HTTPS. You can also use this command to connect to a Windows VM using Windows Admin Center (WAC) if the WAC extension is installed on the target VM.
VEOF
}

output "bastion_command_native_rdp" {
  description = "Bastion RDP command to access a Windows VM (via native client) - only works with Standard or Premium Bastion SKUs"
  sensitive   = false
  value       = <<VEOF
## Remote RDP connections to VMs that are joined to Microsoft Entra ID is allowed only from Windows 10 or later PCs that are either Microsoft Entra registered, Microsoft Entra joined, or Microsoft Entra hybrid joined to the same directory as the VM.
az network bastion rdp --name ${module.avm-res-network-bastionhost.name} --resource-group ${module.environment_resource_group.resource.name} --target-resource-id vm-name
VEOF
}

output "bastion_command_native_ssh" {
  description = "Bastion SSH command to access a Linux VM (via native client) - only works with Standard or Premium Bastion SKUs"
  sensitive   = false
  value       = <<VEOF
## Bastion SSH command to access a Linux VM (via native client) - only works with Standard or Premium Bastion SKUs
az network bastion ssh --name ${module.avm-res-network-bastionhost.name} --resource-group ${module.environment_resource_group.resource.name} --target-resource-id vm-name
VEOF
}
