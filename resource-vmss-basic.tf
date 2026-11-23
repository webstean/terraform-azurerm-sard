locals {
  vmss_friendly_name                  = "Virtual Machine Scale Set"
  vmss_name                           = substr("vmss${var.prefix}", 0, 8) ## can only be 9 characters or less
  vmss_name_location                  = lower("${local.vmss_name}${lower(var.location)}")
  vmss_random_suffix                  = substr(random_string.environment.result, 0, 6)
  vmss_name_hostname                  = lower(substr(replace("v${local.vmss_random_suffix}${local.vmss_name_location}", "-", ""), 0, 24))
  vmss_number_of_instances            = var.vmss_number_of_instances
  vmss_admin_username                 = "azureuser"
  vmss_accelerated_networking_enabled = true
  vmss_spot_instances                 = false
  vmss_ultra_ssd_support              = false
  vmss_hibernate_enabled              = var.vmss_hibernation_enabled
  vmss_enable_standby_pool            = false    ## To be true, this needs special permissions setup: https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/standby-pools-configure-permissions
  vmss_patching_mode                  = "Manual" ## "Rolling", "Automatic", "Manual"
}
