locals {
  databox_friendly_name      = "Azure DataBox Gateway"
  databox_name               = "databox-${var.prefix}"
  databox_name_location      = "${local.databox_name}-${lower(var.location)}"
  databox_name_random_suffix = substr(md5(local.databox_name_location), 0, 6)
  databox_name_hostname      = lower(substr(replace("d${local.databox_name_random_suffix}${local.databox_name_location}", "-", ""), 0, 24))
}

resource "azurerm_databox_edge_device" "gateway" {
  name                = local.databox_name_hostname
  resource_group_name = module.environment_resource_group.resource.name
  ## Supported locations are 'eastus','westeurope','southeastasia'
  location = "southeastasia"

  sku_name = "Gateway-Standard"
  tags     = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

output "databox_gateway_id" {
  description = "The ID of the Databox Edge Gateway device."
  value       = azurerm_databox_edge_device.gateway.id
}

output "databox_gateway_properties" {
  description = "The properties of the Databox Edge Gateway device."
  value       = azurerm_databox_edge_device.gateway.device_properties
}
