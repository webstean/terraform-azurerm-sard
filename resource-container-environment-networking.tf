locals {
  aca_env_name          = "aca-env-${var.prefix}"
  aca_env_name_location = lower("${local.aca_env_name}-${lower(var.location)}")
  aca_env_random_suffix = substr(random_string.environment.result, 0, 6)
  aca_env_name_hostname = lower(substr(replace("a${local.aca_env_random_suffix}${var.prefix}${local.aca_env_name_location}", "-", ""), 0, 24))
  aca_sandbox_name      = "${var.prefix}-sandbox"
}

module "containerappenv_subnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm//modules/subnet"
  version = "~> 0.22, < 1.0"

  name             = "containerappenv-${var.prefix}"
  parent_id        = module.virtual_network.resource_id
  address_prefixes = [format("10.%s.12.0/23", local.regions[var.location].location_number)]

  default_outbound_access_enabled               = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true
  service_endpoints                             = tobool(var.deploy_private_endpoints) ? [] : local.service_endpoints
  private_link_service_network_policies_enabled = tobool(var.deploy_private_link_service) ? true : false
  ## Supported values: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled.
  ## Keep this as Enabled so private endpoint network policies remain active on this subnet unless a workload explicitly requires policy exemptions.
  private_endpoint_network_policies = tobool(var.deploy_private_endpoints) ? "Enabled" : "Disabled"

  delegations = [{
    name = "containerappenv-delegation"
    service_delegation = {
      name = "Microsoft.App/environments"
    }
  }]
  route_table = {
    id = azurerm_route_table.this.id
  }
  nat_gateway = var.deploy_nat_gateway ? { id = module.nat_gateway[0].resource_id } : null
  network_security_group = {
    id = (tobool(var.data_pii) || tobool(var.data_phi)) ? azurerm_network_security_group.secure.id : azurerm_network_security_group.any2any.id
  }
  depends_on = [
    azurerm_route_table.this,
    module.virtual_network,
    azurerm_network_security_group.secure,
    azurerm_network_security_group.any2any,
    module.nat_gateway
  ]

}

module "sandbox_subnet" {
  count = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? 0 : 1

  source  = "Azure/avm-res-network-virtualnetwork/azurerm//modules/subnet"
  version = "~> 0.22, < 1.0"

  name             = "sandboxcontainers-${var.prefix}"
  parent_id        = module.virtual_network.resource_id
  address_prefixes = [format("10.%s.86.0/23", local.regions[var.location].location_number)]

  default_outbound_access_enabled               = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true
  service_endpoints                             = tobool(var.deploy_private_endpoints) ? [] : local.service_endpoints
  private_link_service_network_policies_enabled = tobool(var.deploy_private_link_service) ? true : false
  ## Supported values: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled.
  ## Keep this as Enabled so private endpoint network policies remain active on this subnet unless a workload explicitly requires policy exemptions.
  private_endpoint_network_policies = tobool(var.deploy_private_endpoints) ? "Enabled" : "Disabled"

  delegations = [{
    name = "sandbox-containers-delegation"
    service_delegation = {
      name = "Microsoft.App/environments"
    }
  }]
  route_table = {
    id = azurerm_route_table.this.id
  }
  #nat_gateway = {
  #  id = var.deploy_nat_gateway ? module.nat_gateway.resource_id : null
  #}
  network_security_group = {
    id = (tobool(var.data_pii) || tobool(var.data_phi)) ? azurerm_network_security_group.secure.id : azurerm_network_security_group.any2any.id
  }
}

# moved {
#   from = azurerm_subnet.sandbox[0]
#   to   = module.sandbox_subnet[0].azapi_resource.subnet
# }
