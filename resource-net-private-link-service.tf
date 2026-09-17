locals {
  pls_friendly_name      = "Private Link Service"
  pls_docs               = "https://learn.microsoft.com/en-us/azure/private-link/"
  pls_name               = "pls-${var.prefix}"
  pls_name_location      = lower("${local.pls_name}-${lower(var.location)}")
  pls_random_suffix      = substr(md5(local.pls_name_location), 0, 6)
  pls_name_hostname      = lower(substr(replace("l${local.pls_random_suffix}${var.prefix}${local.pls_name_location}", "-", ""), 0, 24))
  proxy_protocol_enabled = true
}

# Private Link Service network policies must be enabled on the subnet used
# for its NAT IP configuration(s).
resource "azurerm_subnet" "pls_nat" {
  count = var.deploy_private_link_service ? 1 : 0

  name                                          = local.pls_name
  resource_group_name                           = module.environment_resource_group.resource.name
  virtual_network_name                          = azurerm_virtual_network.this.name
  address_prefixes                              = [format("10.%s.66.0/24", local.regions[var.location].location_number)]
  private_link_service_network_policies_enabled = false
  ## Possible values are Disabled, Enabled, NetworkSecurityGroupEnabled and RouteTableEnabled.
  private_endpoint_network_policies = "Enabled"
}

# --- Internal Standard Load Balancer fronting the service ------------------
# Placeholder backend pool/probe/rule so the LB is functional out of the box.
# Point the backend pool at your real NICs/VMSS and adjust the probe/rule to
# match your service's actual port.
module "pls_load_balancer" {
  count = var.deploy_private_link_service ? 1 : 0

  source           = "Azure/avm-res-network-loadbalancer/azurerm"
  version          = "~>0.5, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                = "lb-local.${local.pls_name}"
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location
  sku                 = "Standard"
  sku_tier            = tobool(var.deploy_private_endpoints) ? "Global" : "Regional"

  frontend_ip_configurations = {
    pls_frontend = {
      name                                   = "pls-frontend"
      frontend_private_ip_subnet_resource_id = azurerm_subnet.pls_nat[0].id
      frontend_private_ip_address_allocation = "Dynamic"
    }
  }

  backend_address_pools = {
    pls = {
      name = "pls-backend-pool"
    }
  }

  lb_probes = {
    pls = {
      name     = "pls-probe"
      protocol = "Tcp"
      port     = var.private_link_service_port
    }
  }

  lb_rules = {
    pls = {
      name                              = "pls-rule"
      frontend_ip_configuration_name    = "pls-frontend"
      protocol                          = "Tcp"
      frontend_port                     = var.private_link_service_port
      backend_port                      = var.private_link_service_port
      backend_address_pool_object_names = ["pls"]
      probe_object_name                 = "pls"
    }
  }

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

# --- Private Link Service ---------------------------------------------------

resource "azurerm_private_link_service" "this" {
  count = var.deploy_private_link_service ? 1 : 0

  name                = local.pls_name_location
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location

  load_balancer_frontend_ip_configuration_ids = [
    module.pls_load_balancer[0].resource.frontend_ip_configuration[0].id,
  ]

  dynamic "nat_ip_configuration" {
    for_each = var.private_link_service_nat_ip_configurations
    content {
      name               = nat_ip_configuration.value.name
      subnet_id          = azurerm_subnet.pls_nat[0].id
      primary            = nat_ip_configuration.value.primary
      private_ip_address = try(nat_ip_configuration.value.private_ip_address, null)
    }
  }

  auto_approval_subscription_ids = var.private_link_service_auto_approval_subscription_ids
  visibility_subscription_ids    = var.private_link_service_visibility_subscription_ids
  proxy_protocol_enabled         = var.private_link_service_proxy_protocol_enabled
  fqdns                          = var.private_link_service_allowed_fqdns
  tags                           = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

output "pls_id" {
  description = <<DESC
The Private Link Service ID. - that customers can connect to
DESC
  sensitive   = false
  value       = try(azurerm_private_link_service.this[0].id, null)
}

output "pls_name" {
  description = <<DESC
The Private Link Service name - that customers can connect to
DESC
  sensitive   = false
  value       = try(azurerm_private_link_service.this[0].name, null)
}

output "pls_alias" {
  description = <<DESC
The Private Link Service global alias that customers can use to connect to this service
 from anywhere.
DESC
  sensitive   = false
  value       = try(azurerm_private_link_service.this[0].alias, null)
}

/*
## at destination
resource "azurerm_private_endpoint" "to_partner_pls" {
  name                = "pe-partner-service"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.consumer.id

  private_service_connection {
    name                              = "psc-partner-service"
    is_manual_connection              = true                     # true = cross-tenant/manual approval flow
    private_connection_resource_alias = azurerm_private_link_service.this[0].alias
    request_message                   = "Requesting access from ${data.azurerm_subscription.current.display_name}"
  }
}
*/
