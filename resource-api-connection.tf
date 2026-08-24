
resource "azurerm_api_connection" "office365-connection" {
  display_name        = var.owner_entra_display_name
  managed_api_id      = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Web/locations/australiaeast/managedApis/office365"
  name                = "office365"
  resource_group_name = module.environment_resource_group.resource.name
  tags                = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  lifecycle {
    # NOTE: since the connectionString is a secure value it's not returned from the API
    ignore_changes = [parameter_values]
  }
}
resource "azurerm_api_connection" "arm-connection" {
  display_name        = var.owner_entra_display_name
  managed_api_id      = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Web/locations/australiaeast/managedApis/arm"
  name                = "arm"
  resource_group_name = module.environment_resource_group.resource.name
  tags                = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  lifecycle {
    # NOTE: since the connectionString is a secure value it's not returned from the API
    ignore_changes = [parameter_values]
  }
}
