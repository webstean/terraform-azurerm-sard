

resource "azurerm_subnet" "sandbox" {
  count = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? 0 : 1

  name                                          = "sandbox-${var.prefix}"
  resource_group_name                           = module.environment_resource_group.resource.name
  virtual_network_name                          = local.vnet_resource_name
  address_prefixes                              = [format("10.%s.87.0/24", local.regions[var.location].location_number)]
  default_outbound_access_enabled               = true
  service_endpoints                             = local.service_endpoints
  private_link_service_network_policies_enabled = false
  ## Supported values: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled.
  ## Keep this as Enabled so private endpoint network policies remain active on this subnet unless a workload explicitly requires policy exemptions.
  private_endpoint_network_policies = tobool(var.deploy_private_endpoints) ? "Enabled" : "Disabled"

  delegation {
    name = "sandbox-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = local.delegation-actions
    }
  }
}

resource "azapi_resource" "sandbox_group" {
  count = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? 0 : 1

  type      = "Microsoft.App/sandboxGroups@2026-02-01-preview"
  name      = "sandbox-group-${var.prefix}"
  parent_id = module.environment_resource_group.resource_id
  location  = module.environment_resource_group.resource.location
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }
  schema_validation_enabled = false
}

resource "azapi_resource" "sandbox_vnet_connection" {
  count = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? 0 : 1

  type      = "Microsoft.App/sandboxGroups/vnetConnections@2026-02-01-preview"
  name      = "default"
  parent_id = azapi_resource.sandbox_group[0].id
  location  = azapi_resource.sandbox_group[0].location

  schema_validation_enabled = false

  body = {
    properties = {
      subnetId = azurerm_subnet.sandbox[0].id
    }
  }
}
