
resource "azurerm_storage_container" "sku_finder_cache" {
  name                  = lower("sku-finder")
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
resource "azurerm_role_assignment" "sku_finder_contributor" {
  scope                = azurerm_storage_container.sku_finder_cache.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

module "vm_x64_skus" {
  source           = "Azure/avm-utl-sku-finder/azapi"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry

  #cache_storage_details = {
  #  storage_account_resource_group_name = azurerm_storage_account.this.resource_group_name
  #  storage_account_name                = azurerm_storage_account.this.name
  #  storage_account_blob_container_name = azurerm_storage_container.sku_finder_cache.name
  #  storage_account_blob_prefix         = "cache"
  #}

  location      = var.location
  resource_type = "vm"
  vm_filters = {
    accelerated_networking_enabled = local.vmss_accelerated_networking_enabled
    cpu_architecture_type          = "x64"
    encryption_at_host_supported   = true
    hibernation_supported          = local.vmss_hibernate_enabled
    hyper_v_generations            = "V2"
    location_ultrassd_support      = true ## local.vmss_ultra_ssd_support ## HERE
    low_priority_capable           = true ## local.vmss_spot_instances ## Spot or not
    min_network_interfaces         = 2
    max_memory_gb                  = 19
    max_vcpus                      = 4
    min_memory_gb                  = 11
    min_vcpus                      = 2
    premium_io_supported           = true
    #rdma_enabled          = false
  }
  cache_results      = true
  local_cache_prefix = "cache"
  depends_on = [
    azurerm_storage_container.sku_finder_cache,
    azurerm_role_assignment.sku_finder_contributor
  ]
}

resource "random_integer" "vm_x64_sku_pick" {
  min = 0
  max = length(module.vm_x64_skus.sku_list) - 1
}
locals {
  virtual_machine_x64_sku_random = tolist(module.vm_x64_skus.sku_list)[0] == "no_valid_skus_found" ? "" : tolist(module.vm_x64_skus.sku_list)[random_integer.vm_x64_sku_pick.result]
}

output "virtual_machine_x64_sku_random" {
  description = "Randomly selected x64 virtual machine SKU"
  sensitive   = false
  value       = try(local.virtual_machine_x64_sku_random, null)
}

output "virtual_machine_x64_sku_list" {
  description = "List of x64 virtual machine SKUs"
  sensitive   = false
  value       = try(module.vm_x64_skus.sku_list, null)
}

