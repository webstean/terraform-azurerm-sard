locals {
  aca_env_name          = "aca-env-${var.prefix}"
  aca_env_name_location = lower("${local.aca_env_name}-${lower(var.location)}")
  aca_env_random_suffix = substr(random_string.environment.result, 0, 6)
  aca_env_name_hostname = lower(substr(replace("a${local.aca_env_random_suffix}${var.prefix}${local.aca_env_name_location}", "-", ""), 0, 24))
}

resource "azurerm_subnet" "containerappenv" {
  name                                          = local.aca_env_name
  resource_group_name                           = module.environment_resource_group.resource.name
  virtual_network_name                          = local.vnet_resource_name
  address_prefixes                              = [format("10.%s.12.0/23", local.regions[var.location].location_number)]
  default_outbound_access_enabled               = true
  service_endpoints                             = local.service_endpoints
  private_link_service_network_policies_enabled = false
  ## Supported values: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled.
  ## Keep this as Enabled so private endpoint network policies remain active on this subnet unless a workload explicitly requires policy exemptions.
  private_endpoint_network_policies = tobool(var.deploy_private_endpoints) ? "Enabled" : "Disabled"

  delegation {
    name = "azure-container-apps-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = local.delegation-actions
    }
  }
}
resource "azurerm_subnet_route_table_association" "subnet_aca_containerapp_route" {
  subnet_id      = azurerm_subnet.containerappenv.id
  route_table_id = azurerm_route_table.this.id
}
resource "azurerm_subnet_nat_gateway_association" "containerappenv" {
  count = var.deploy_nat_gateway ? 1 : 0

  subnet_id      = azurerm_subnet.containerappenv.id
  nat_gateway_id = module.nat_gateway[0].resource_id
}

resource "azurerm_subnet" "aca_sandbox" {
  name                                          = "aca_sandbox"
  resource_group_name                           = module.environment_resource_group.resource.name
  virtual_network_name                          = local.vnet_resource_name
  address_prefixes                              = [format("10.%s.20.0/24", local.regions[var.location].location_number)]
  default_outbound_access_enabled               = true
  service_endpoints                             = local.service_endpoints
  private_link_service_network_policies_enabled = false
  ## Supported values: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled.
  ## Keep this as Enabled so private endpoint network policies remain active on this subnet unless a workload explicitly requires policy exemptions.
  private_endpoint_network_policies = tobool(var.deploy_private_endpoints) ? "Enabled" : "Disabled"

  delegation {
    name = "azure-container-apps-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = local.delegation-actions
    }
  }
}
resource "azurerm_subnet_route_table_association" "subnet_aca_sandbox_route" {
  subnet_id      = azurerm_subnet.aca_sandbox.id
  route_table_id = azurerm_route_table.this.id
}

