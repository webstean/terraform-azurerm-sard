locals {
  fluid_relay_friendly_name = "Fluid Framework Relay"
  fluid_relay_docs          = "https://learn.microsoft.com/en-us/azure/azure-fluid-relay/"
  fluid_name                = "fluid-relay-${var.prefix}"
  fluid_name_location       = lower("${local.fluid_name}-${lower(var.location)}")
  fluid_random_suffix       = substr(random_string.environment.result, 0, 6)
  fluid_name_hostname       = lower(substr(replace("f${local.fluid_random_suffix}${local.fluid_name_location}", "-", ""), 0, 24))
  fluid_sku                 = "basic"
}

resource "azurerm_fluid_relay_server" "this" { ## Takes a long time to deploy
  name                = local.fluid_name_hostname
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location

  storage_sku = local.fluid_sku
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

output "fluid_relay_service_id" {
  description = "The ID of the Fluid Relay service."
  sensitive   = false
  value       = try(azurerm_fluid_relay_server.this.id, null)
}

output "fluid_relay_service_endpoints" {
  description = "The service endpoints of the Fluid Relay service."
  sensitive   = false
  value       = try(azurerm_fluid_relay_server.this.service_endpoints, null)
}

output "fluid_relay_server_primary_key" {
  description = "The primary key of the Fluid Relay service."
  sensitive   = false
  value       = try(azurerm_fluid_relay_server.this.primary_key, null)
}

output "fluid_relay_server_secondary_key" {
  description = "The secondary key of the Fluid Relay service."
  sensitive   = false
  value       = try(azurerm_fluid_relay_server.this.secondary_key, null)
}

