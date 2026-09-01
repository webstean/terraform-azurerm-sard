locals {
  vnet_friendly_name = "Virtual Network"
  vnet_name          = "vnet-${var.prefix}"
  vnet_name_location = lower("${local.vnet_name}-${lower(var.location)}")
  vnet_random_suffix = substr(md5(local.vnet_name_location), 0, 6)
  vnet_name_hostname = lower(substr(replace("l${local.vnet_random_suffix}${local.vnet_name_location}", "-", ""), 0, 24))
}

## https://blog.cloudtrooper.net/2023/02/06/virtual-network-gateways-routing-in-azure/

/*
Extended Zones
Get-AzEdgeZonesExtendedZone
Register-AzEdgeZonesExtendedZone -Name 'perth'
Get-AzEdgeZonesExtendedZone -Name 'perth'
*/

resource "azurerm_virtual_network" "this" {
  name                = local.vnet_name_location
  location            = module.environment_resource_group.resource.location
  resource_group_name = module.environment_resource_group.resource.name

  address_space = local.regions[var.location].vnet_address_space
  bgp_community = local.regions[var.location].vnet_bgp_community
  ## dns_servers       = local.regions[var.location].dns_servers

  encryption {
    enforcement = "AllowUnencrypted"
  }

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

resource "azurerm_subnet" "outbound" {
  name                 = "outbound"
  resource_group_name  = module.environment_resource_group.resource.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [format("10.%s.99.0/24", local.regions[var.location].location_number)]
  ## Note, the VMSS won't use the default Internet outbound (even if enabled - you have to use a NAT Gateway)
  default_outbound_access_enabled               = true
  service_endpoints                             = var.deploy_private_endpoints ? null : local.service_endpoints
  private_link_service_network_policies_enabled = false
  ## Possible values are Disabled, Enabled, NetworkSecurityGroupEnabled and RouteTableEnabled.
  private_endpoint_network_policies = "Enabled"
  #service_endpoint_policy_ids = [
  #  azurerm_subnet_service_endpoint_storage_policy.storage.id
  #]
}

/*
resource "azurerm_monitor_diagnostic_setting" "vnet-metrics" {
  name                       = "Metrics-${azurerm_virtual_network.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_virtual_network.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
resource "azurerm_monitor_diagnostic_setting" "vnet_logs" {
  name                       = "Logs-${azurerm_virtual_network.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_virtual_network.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
}
*/

# Route table with direct-to-internet routes for Windows KMS activation endpoints
# Activation needs to come from a Azure IP Address, not from a private IP address, so we need to route traffic to the Internet for the KMS endpoints
resource "azurerm_route_table" "this" {
  name                          = "Direct-Internet-Routes"
  resource_group_name           = module.environment_resource_group.resource.name
  location                      = module.environment_resource_group.resource.location
  bgp_route_propagation_enabled = false ## keep them, as simple static routes

  route {
    name           = "DirectRouteToKMS" ## Windows Activation
    address_prefix = "23.102.135.246/32"
    next_hop_type  = "Internet" ## Possible values are VirtualNetworkGateway (On-Premise), VnetLocal, Internet, VirtualAppliance and None.
  }

  route {
    name           = "DirectRouteToAZKMS01" ## Windows Activation
    address_prefix = "20.118.99.224/32"
    next_hop_type  = "Internet" ## Possible values are VirtualNetworkGateway, VnetLocal, Internet, VirtualAppliance and None.
  }

  route {
    name           = "DirectRouteToAZKMS02" ## Windows Activation
    address_prefix = "40.83.235.53/32"
    next_hop_type  = "Internet" ## Possible values are VirtualNetworkGateway, VnetLocal, Internet, VirtualAppliance and None.
  }

  route {
    name           = "DirectRouteToTeamsTURN" ## voice, video for MS Teams
    address_prefix = "20.202.0.0/16"
    next_hop_type  = "Internet" ## Possible values are VirtualNetworkGateway, VnetLocal, Internet, VirtualAppliance and None.
  }

  route {
    name           = "DirectRouteToGoogleDNS1" ## Google DNS
    address_prefix = "8.8.8.8/32"
    next_hop_type  = "Internet" ## Possible values are VirtualNetworkGateway, VnetLocal, Internet, VirtualAppliance and None.
  }

  route {
    name           = "DirectRouteToGoogleDNS2" ## Google DNS
    address_prefix = "8.8.4.4/32"
    next_hop_type  = "Internet" ## Possible values are VirtualNetworkGateway, VnetLocal, Internet, VirtualAppliance and None.
  }

  route {
    name           = "DirectRouteToCloudflareDNS1" ## Cloudflare DNS
    address_prefix = "1.1.1.1/32"
    next_hop_type  = "Internet" ## Possible values are VirtualNetworkGateway, VnetLocal, Internet, VirtualAppliance and None.
  }

  route {
    name           = "DirectRouteToCloudflareDNS2" ## Cloudflare DNS
    address_prefix = "1.0.0.1/32"
    next_hop_type  = "Internet" ## Possible values are VirtualNetworkGateway, VnetLocal, Internet, VirtualAppliance and None.
  }

  ## to route traffic to a Secure vWAN (see routing intent) - do not use a route table, like this one.
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

## Attach the route table to the subnet hosting the VMs
resource "azurerm_subnet_route_table_association" "subnet01_kms_route" {
  subnet_id      = azurerm_subnet.outbound.id
  route_table_id = azurerm_route_table.this.id
}

## Send traffic in vWAN hub to the Firewall
## This avoids having to use UDR (User Defined Routes)
resource "azurerm_virtual_hub_routing_intent" "this" {
  count = (var.vwan_hub_id != null && var.vwan_hub_firewall_id != null) ? 1 : 0

  name           = "routing-intent-for-vwan"
  virtual_hub_id = var.vwan_hub_id

  routing_policy {
    name         = "PrivateTraffic"
    destinations = ["PrivateTraffic"]
    next_hop     = var.vwan_hub_firewall_id
  }

  routing_policy {
    name         = "InternetTraffic"
    destinations = ["Internet"]
    next_hop     = var.vwan_hub_firewall_id
  }
}

resource "azurerm_network_security_group" "general" { ## designed to be associated to NIC or subnets or both!
  name                = "nsg-general-access-${lower(module.environment_resource_group.resource.location)}"
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location

  ## ===========================================================================================================
  ## Outbound: Azure Instance Metadata Service endpoint
  security_rule {
    name                       = "Allow-OutBound-To-Azure-Metadata-endpoint"
    priority                   = 101
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "169.254.169.254" ## Service Tag: "AzurePlatformIMDS" but can only be used on deny rule
    description                = "Allow access to internal Azure Instance Metadata Service (IMDS)"
  }
  ## Outbound: WireServer
  security_rule {
    name                       = "Allow-OutBound-To-Azure-WireServer"
    priority                   = 102
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["53", "80", "443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "168.63.129.16" ## Service Tag: "AzurePlatformDNS"  but can only be used on deny rule
    description                = "Allow access to WireServer for DHCP, DNS, extension, load balancer probes, and internal Azure DNS service (for lookups)"
  }
  ## Outbound: Any DNS
  security_rule {
    name                       = "Allow-Outbound-to-Any-DNS"
    priority                   = 109
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "53"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
    description                = "Allow access to any DNS service (for lookups/troubleshooting)"
  }

  ## HTTPS - Outbound (Azure AD (Entra ID))
  security_rule {
    name                       = "Allow-Outbound-Entra-ID"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureActiveDirectory"
    description                = "Allow Outbound access to Entra ID (AAD - Azure Active Directory) also needed for WindowsAdminCenter"
  }

  // Outbound HTTPS to WindowsAdminCenter
  security_rule {
    name                       = "Allow-Outbound-WindowsAdminCenter"
    priority                   = 121
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "WindowsAdminCenter"
    description                = "Allow Outbound access to the Windows Admin Centre service"
  }

  // Outbound HTTPS to Intune1
  security_rule {
    name                       = "Allow-Outbound-MicrosoftIntune1"
    priority                   = 122
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "5671"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "MicrosoftIntune"
    description                = "Allow Outbound access to Microsoft Intune"
  }
  // Outbound HTTPS to Intune2
  security_rule {
    name                       = "Allow-Outbound-MicrosoftIntune2"
    priority                   = 123
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureFrontDoor.MicrosoftSecurity"
    description                = "Allow Outbound access to Azure Front Door Microsoft Security (for Intune)"
  }

  ## ICMP (ping) - Inbound (VirtualNetwork)
  security_rule {
    name                       = "Allow-Inbound-ICMP-between-VNets"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow ping/psping for connectivity checks/troubleshooting between VirtualNetworks within Azure"
  }
  ## ICMP (ping) - Outbound (VirtualNetwork)
  security_rule {
    name                       = "Allow-Outbound-ICMP-between-VNets"
    priority                   = 131
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow ping/psping for connectivity checks/troubleshooting between VirtualNetworks within Azure"
  }
  ## ICMP (ping) - Inbound (Internet)
  security_rule {
    name                       = "Allow-Inbound-ICMP-to-Any"
    priority                   = 132
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow inbound pings for connectivity checks/troubleshooting"
  }
  ## ICMP (ping) - Outbound (Internet)
  security_rule {
    name                       = "Allow-Outbound-ICMP-to-Any"
    priority                   = 133
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
    description                = "Allow outbound pings for connectivity checks/troubleshooting"
  }
  ## Inbound: Bastian (other than Developer SKU)
  security_rule {
    name                       = "Allow-Bastian-Non-Developer-SKUs"
    priority                   = 141
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22", "3389"]
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow Azure Bastian access via both SSH and RDP"
  }
  ## Inbound: Bastian (Developer SKU)
  security_rule {
    name                       = "Allow-Bastian-Developer-SKU"
    priority                   = 142
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22", "3389"]
    source_address_prefix      = "168.63.129.16"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow Azure Bastian Developer access to both SSH and RDP"
  }

  ## HTTPS - Outbound (VirtualNetworks)
  security_rule {
    name                       = "Allow-Outbound-Https-between-VirtualNetworks"
    priority                   = 150
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "5000", "5001", "8080", "8443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow HTTPS, DOTNet etc... between VirtualNetworks"
  }
  ## HTTPS - Inbound (VirtualNetworks)
  #security_rule {
  #  name                       = "Allow-Inbound-Https-between-VirtualNetworks"
  #  priority                   = 151
  #  direction                  = "Inbound"
  #  access                     = "Allow"
  #  protocol                   = "Tcp"
  #  source_port_ranges         = ["80", "443", "5000", "5001", "8080", "8443"]
  #  destination_port_range     = "*"
  #  source_address_prefix      = "VirtualNetwork"
  #  destination_address_prefix = "VirtualNetwork"
  #  description                = "Allow HTTPS, DOTNet etc... between VirtualNetworks"
  #}

  ## HTTPS - Outbound (Azure)
  security_rule {
    name                       = "Allow-Outbound-Https-within-Azure"
    priority                   = 160
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "5000", "5001", "8080", "8443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
    description                = "Allow HTTPS, DOTNet etc... within Azure"
  }

  ## HTTPS - Outbound (Any)
  security_rule {
    name                       = "Allow-Outbound-Https-to-Any"
    priority                   = 500
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "5000", "5001", "8080", "8443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
    description                = "Allow HTTPS, DOTNet etc... to Any"
  }
  ## HTTPS - Inbound (any)
  security_rule {
    name                       = "Allow-Inbound-Https-from-Vnets"
    priority                   = 600
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "5000", "5001", "8080", "8443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Inbound Allow HTTPS from any virtual networks"
  }
  ## SSH/RDP (intended to be only via bastian)
  security_rule {
    name                       = "Allow-Inbound-Https-from-Gateways"
    priority                   = 700
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22", "80", "443", "5000", "5001", "8080", "8443"]
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow SSH from Azure Gateways [so not from the Internet] (expected to be Bastian)"
  }
  ## SSH/RDP (intended to be only via bastian)
  security_rule {
    name                       = "Allow-Inbound-Https-from-NLB"
    priority                   = 800
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "5000", "5001", "8080", "8443"]
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow RDP from Azure Load Balancer [so not from the Internet] (expected to be Bastian)"
  }
  #  // Outbound: KMS azkms.core.windows.net and kms.core.windows.net
  #  security_rule {
  #    name                   = "Allow-Outbound-Azure-Windows-KMS"
  #    priority               = 900
  #    direction              = "Outbound"
  #    access                 = "Allow"
  #    protocol               = "*"
  #    source_port_range      = "*"
  #    destination_port_range = "1688"
  #    source_address_prefix  = "VirtualNetwork"
  #    ## Service Tag: "AzurePlatformLKM" but can only be used on deny rule
  #    ## destination_address_prefixes = ["20.118.99.224", "40.83.235.53", "23.102.135.246", "azkms.core.windows.net", "kms.core.windows.net"]
  #    ## Test-NetConnection azkms.core.windows.net -Port 1688
  #    ## psping kms.core.windows.net:1688
  #    ## psping azkms.core.windows.net:1688
  #    destination_address_prefixes = ["20.118.99.224", "40.83.235.53", "23.102.135.246"]
  #    description                  = "Allow Outbound to Azure KMS for Windows activation/licensing"
  #  }
  // Inbound HTTPS/6516 for WindowsAdminCenter
  security_rule {
    name                       = "Allow-Inbound-WindowsAdminCenter-Port-6516"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6516"
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow-Inbound-AdminCenter-from-Any (including Internet)"
  }
  ## WinRM (for Packer and others)
  security_rule {
    name                       = "Inbound-Allow-WinRM-PowerShell-between-vNETs"
    priority                   = 1100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["5985-5986"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Allow Inbound WinRM/PowerShell between VNets (for Packer and others)"
  }
  ## Outbound: Entra ID Domain Services
  security_rule {
    name                       = "Outbound-Allow-Entra-Domain-Services"
    priority                   = 1200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "88", "443", "468", "3268-3269"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureActiveDirectoryDomainServices"
    description                = "Allow Outbound Entra ID Domain Services (Active Directory) for LDAP, Kerberos, LDAPS, Global Catalog"
  }
  ## Outbound: Windows 365, AVD, Devbox (UDP)
  security_rule {
    name                       = "Outbound-Allow-TURN-Audio-MSTeams"
    priority                   = 1300
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "3478"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "20.202.0.0/16"
    description                = "Outbound TURN for Microsoft Teams Audio"
  }
  ## Outbound: Kerberos/SMB storage
  ## TCP Port 88: Used for Kerberos authentication.
  ## TCP Port 135: Required for RPC (Remote Procedure Call) services.
  ## TCP Port 139: Used for NetBIOS session service.
  ## TCP Port 445: Necessary for SMB (Server Message Block) protocol.
  ## TCP Port 464: Used for Kerberos password changes.
  ## TCP Port 3268 and 3269: Required for Global Catalog services.
  ## Ephemeral Ports: TCP and UDP ports 49152-65535 for dynamic port allocation
  security_rule {
    name                       = "Outbound-SMB-Kerberos-VirtualNetwork"
    priority                   = 1400
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["88", "135", "139", "445", "464", "3268-3269"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Outbound Windows Storage access (private endpoints)"
  }
  security_rule {
    name                       = "Outbound-SMB-Kerberos-Azure"
    priority                   = 1500
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["88", "135", "139", "445", "464", "3268-3269"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
    description                = "Outbound Windows Storage access (public (including service) endpoints)"
  }
  security_rule {
    name                       = "Deny-SMB-Kerberos-Internet"
    priority                   = 1600
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["88", "135", "139", "445", "464", "3268-3269"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
    description                = "Deny Outbound Kerberos Storage access (over Internet)"
  }
  ## Ephemeral Ports: TCP and UDP ports 49152-65535 for dynamic port allocation
  security_rule {
    name                       = "Outbound-SMB-Storage-Ephemeral-VirtualNetwork"
    priority                   = 1700
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["49152-65535"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
    description                = "Outbound SMB Storage access"
  }
  security_rule {
    name                       = "Outbound-SMB-Storage-Ephemeral-Azure"
    priority                   = 1800
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["49152-65535"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
    description                = "Outbound SMB Storage access"
  }
  security_rule {
    name                       = "Outbound-SMB-Storage-Ephemeral-Internet"
    priority                   = 1900
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["49152-65535"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
    description                = "Outbound Windows Storage access"
  }

  // Outbound: Windows 365, AVD, Devbox (UDP)
  // https://learn.microsoft.com/en-us/windows-365/enterprise/azure-firewall-windows-365

  # Allow TCP 2049 (for NFS)
  security_rule {
    name                       = "Outbound-NFS"
    priority                   = 1910
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["2049"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
    description                = "Outbound NFS Storage access"
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
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Deny ALL Outbound as part of Zero Trust Networking"
  }

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

resource "azurerm_subnet_network_security_group_association" "general1" {
  subnet_id                 = azurerm_subnet.outbound.id
  network_security_group_id = azurerm_network_security_group.general.id
}

/*
## NO LONGER - supported by Azure
resource "azurerm_network_watcher_flow_log" "vnet" {
  count = var.deploy_vnet ? 1 : 0

  name = "${azurerm_virtual_network.this.name}-flow-log"
  // This watcher is automatically created by Azure (one per region, when you create a Vnet)
  network_watcher_name = format("NetworkWatcher_%s", lower(azurerm_virtual_network.this.location))
  resource_group_name  = "NetworkWatcherRG"

  ## network_security_group_id = azurerm_network_security_group.vnet[each.key].id
  target_resource_id = azurerm_network_security_group.general.id
  storage_account_id = azurerm_storage_account.this.id
  enabled            = true
  version            = "2"

  retention_policy {
    enabled = true
    days    = 7
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = module.log_analytics_workspace.resource_id
    workspace_region      = module.log_analytics_workspace.location
    workspace_resource_id = module.log_analytics_workspace.resource_id
    interval_in_minutes   = 10
  }
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

resource "azurerm_network_connection_monitor" "sql_1433" {
  name               = "cm-vm-to-sql-1433"
  network_watcher_id = azurerm_network_watcher.this.id
  location           = azurerm_network_watcher.this.location

  endpoint {
    name               = "source-vm"
    target_resource_id = azurerm_windows_virtual_machine.source.id
  }

  endpoint {
    name    = "sql-server"
    address = "my-sql-server.database.windows.net"
  }

  test_configuration {
    name                      = "tcp-1433"
    protocol                  = "Tcp"
    test_frequency_in_seconds = 60

    tcp_configuration {
      port = 1433
    }

    success_threshold {
      checks_failed_percent = 10
      round_trip_time_ms    = 500
    }
  }

  test_group {
    name                     = "vm-to-sql"
    destination_endpoints    = ["sql-server"]
    source_endpoints         = ["source-vm"]
    test_configuration_names = ["tcp-1433"]
    enabled                  = true
  }

  depends_on = [
    azurerm_virtual_machine_extension.network_watcher
  ]
}
*/

/*
locals {
  ## subnet id for service endpoints
  application_subnet_ids = [
    for subnet in azurerm_subnet.application_subnets :
    subnet.id
  ]
  ## only include subnets that are not used for PII/PHI data
  conditional_application_subnet_ids = (var.data_pii == true || var.data_phi == true) ? [] : [
    for subnet in azurerm_subnet.application_subnets : subnet.id
  ]
  storage_service_endpoint_subnets_ids = (var.data_pii == true || var.data_phi == true) ? [] : [
    for subnet in azurerm_subnet.application_subnets : subnet.id
    if subnet.service_endpoints != null && contains(subnet.service_endpoints, "Microsoft.Storage.Global")
  ]
  container_registry_service_endpoint_subnets_ids = (var.data_pii == true || var.data_phi == true) ? [] : [
    for subnet in azurerm_subnet.application_subnets : subnet.id
    if subnet.service_endpoints != null && contains(tolist(subnet.service_endpoints), "Microsoft.ContainerRegistry")
  ]
  cosmos_service_endpoint_subnets_ids = (var.data_pii == true || var.data_phi == true) ? [] : [
    for subnet in azurerm_subnet.application_subnets : subnet.id
    if subnet.service_endpoints != null && contains(tolist(subnet.service_endpoints), "Microsoft.AzureCosmosDB")
  ]
  eventhub_service_endpoint_subnets_ids = (var.data_pii == true || var.data_phi == true) ? [] : [
    for subnet in azurerm_subnet.application_subnets : subnet.id
    if subnet.service_endpoints != null && contains(tolist(subnet.service_endpoints), "Microsoft.EventHub")
  ]
  keyvault_service_endpoint_subnets_ids = (var.data_pii == true || var.data_phi == true) ? [] : [
    for subnet in azurerm_subnet.application_subnets : subnet.id
    if subnet.service_endpoints != null && contains(tolist(subnet.service_endpoints), "Microsoft.KeyVault")
  ]
  servicebus_service_endpoint_subnets_ids = (var.data_pii == true || var.data_phi == true) ? [] : [
    for subnet in azurerm_subnet.application_subnets : subnet.id
    if subnet.service_endpoints != null && contains(tolist(subnet.service_endpoints), "Microsoft.ServiceBus")
  ]
  sql_server_endpoint_subnets_ids = (var.data_pii == true || var.data_phi == true) ? [] : [
    for subnet in azurerm_subnet.application_subnets : subnet.id
    if subnet.service_endpoints != null && contains(tolist(subnet.service_endpoints), "Microsoft.Sql")
  ]
  web_service_endpoint_subnets_ids = (var.data_pii == true || var.data_phi == true) ? [] : [
    for subnet in azurerm_subnet.application_subnets : subnet.id
    if subnet.service_endpoints != null && contains(tolist(subnet.service_endpoints), "Microsoft.Web") // Azure App Services)
  ]
}

output "subnet_service_endpoints" {
  description = "Map of subnet IDs with their enabled service endpoints"
  value = {
    "Microsoft.Storage.Global"    = local.storage_service_endpoint_subnets_ids
    "Microsoft.ContainerRegistry" = local.container_registry_service_endpoint_subnets_ids
    "Microsoft.AzureCosmosDB"     = local.cosmos_service_endpoint_subnets_ids
    "Microsoft.EventHub"          = local.eventhub_service_endpoint_subnets_ids
    "Microsoft.KeyVault"          = local.keyvault_service_endpoint_subnets_ids
    "Microsoft.ServiceBus"        = local.servicebus_service_endpoint_subnets_ids
    "Microsoft.Sql"               = local.sql_server_endpoint_subnets_ids
    "Microsoft.Web"               = local.web_service_endpoint_subnets_ids
  }
}
*/


/*
resource "azurerm_subnet" "subnets" {
  // for_each = local.subnets
  // for_each = { for subnet in local.subnets : subnet.name => subnet }

  for_each = {
    for region, region_label in local.regions :
    for subnet_name, subnet_props in local.subnets :
    "${region}-${subnet_name}" => {
      region        = region
      subnet_name   = subnet_name
      subnet_cidr   = "${replace(local.vnet_cidr_per_region[region], "/16", "")}${subnet_props.cidr_suffix}"
      delegation    = subnet_props.delegation
    }
  }

  name                 = each.value.subnet_name
  resource_group_name  = azurerm_resource_group.rg[each.value.region].name
  virtual_network_name = azurerm_virtual_network.vnet[each.value.region].name
  address_prefixes     = [each.value.subnet_cidr]

  service_endpoints    = each.value.service_endpoints
  default_outbound_access_enabled = local.outbound_internet_access
  private_endpoint_network_policies = each.value.private_endpoint_network_policies
  private_link_service_network_policies_enabled = each.key == "private-link-service" ? true : false

  dynamic "delegation" {
    for_each = each.value.delegation != null ? [each.value.delegation] : []
    content {
      name = delegation.value.name

      service_delegation {
        name    = delegation.value.service_delegation.name
        actions = delegation.value.service_delegation.actions
      }
    }
  }

  depends_on = [
    azurerm_virtual_network.vnet
  ]
  lifecycle {
    create_before_destroy = true
  }

}
*/


/*
output "virtualnetwork_subnets_ids" {
  value = data.azurerm_subnet.*.name
}
data.azurerm_virtual_network.vnet.subnet.*.id

*/

/*
data "azurerm_subnet" "melbourne" {
  // for_each = azurerm_virtual_network.vnet

  name                 = data.azurerm_virtual_network.vnet["melbourne"].subnets[count.index]
  virtual_network_name = data.azurerm_virtual_network.vnet["melbourne"].name
  resource_group_name  = data.azurerm_virtual_network.vnet["melbourne"].resource_group_name
  count                = length(data.azurerm_virtual_network.vnet["melbourne"].subnets)
}
*/

/*
output "virtualnetwork_subnets_melbourne" {
  value = data.azurerm_subnet.melbourne
}
*/


/*
data "azurerm_virtual_network" "azure_vnet_details" {
  [ for each in azurerm_virtual_network.vnet : each.key => each.value

    name                 = each.value.subnets[count.index]
    virtual_network_name = each.value.name
    resource_group_name  = each.value.resource_group_name
    count                = length(each.value.subnets)
  ]
}
*/

locals {
  subnet_details = tomap({
    for snet in azurerm_virtual_network.this.subnet : snet.name => {
      id                = snet.id
      address_prefixes  = snet.address_prefixes
      service_endpoints = try(snet.service_endpoints, [])
      name              = snet.name
    }
  })
}
output "vnet_subnet_details" {
  description = "The details of the subnets within the virtual network."
  sensitive   = false
  value       = local.subnet_details
}

/*
locals {
  instance_ids = concat(azurerm_virtual_network.vnet.*.name, azurerm_virtual_network.vnet.*.name)
}
output "azure_vnet_instance_ids" {
  value = local.instance_ids
}
*/

/*
output "azure_subnet_ids" {
  value = [ for subnets in data.azurerm_virtual_network.vnet.subnet : subnets.id ]
}
*/

/*

// Get a list of subnets
data azurerm_subnet "subnets" {
  for_each = local.regions

  count = length(data.azurerm_virtual_network.vnet[each.key].subnets)

  name                 = data.azurerm_virtual_network.vnet[each.key].subnets[count.index]
  virtual_network_name = azurerm_virtual_network.vnet[each.key].vnet_name
  resource_group_name  = azurerm_virtual_network.vnet[each.key].resource_group
}

*/
