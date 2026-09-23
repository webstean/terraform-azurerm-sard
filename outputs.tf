output "azure_location_details" {
  description = "Details of the location being used with this subscription."
  sensitive   = false
  value = {
    id            = data.azurerm_location.current.id
    display_name  = data.azurerm_location.current.display_name
    zone_mappings = data.azurerm_location.current.zone_mappings
  }
}
