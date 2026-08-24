locals {
  vmss_friendly_name                  = "Virtual Machine Scale Set"
  vmss_name                           = substr("vmss${var.prefix}", 0, 8) ## can only be 9 characters or less
  vmss_name_location                  = lower("${local.vmss_name}${lower(var.location)}")
  vmss_random_suffix                  = substr(md5(local.vmss_name_location), 0, 6)
  vmss_name_hostname                  = lower(substr(replace("cc${local.vmss_random_suffix}${local.vmss_name_location}", "-", ""), 0, 24))
  vmss_number_of_instances            = var.vmss_number_of_instances
  vmss_admin_username                 = "azureuser"
  vmss_accelerated_networking_enabled = true
  vmss_spot_instances                 = false
  vmss_ultra_ssd_support              = false
  vmss_hibernate_enabled              = true
  vmss_enable_standby_pool            = false
  vmss_patching_mode                  = "Manual" ## "Automatic"
  vmss_subnet_id                      = azurerm_subnet.outbound.id
}

locals {
  nat_friendly_name = "NAT Gateway"
  nat_name          = var.prefix
  nat_name_location = lower("${local.nat_name}-${lower(var.location)}")
  nat_random_suffix = substr(md5(local.nat_name_location), 0, 6)
  nat_name_hostname = lower(substr(replace("l${local.nat_random_suffix}${local.nat_name_location}", "-", ""), 0, 24))
}

resource "azurerm_public_ip" "nat" {
  count = var.vmss_number_of_instances == 0 || var.vmss_autoscale_enabled == false ? 0 : 1

  name                = "pip-${local.nat_name_location}"
  allocation_method   = "Static"
  location            = azurerm_resource_group.environment.location
  resource_group_name = azurerm_resource_group.environment.name
  sku                 = "StandardV2"
  sku_tier            = "Regional" ## "Global"
  #domain_name_label = local.vmms_name_hostname
  #domain_name_label_scope = "TenantReuse" # (Optional) Scope for the domain name label. If a domain name label scope is specified,
  # an A DNS record is created for the public IP in the Microsoft Azure DNS system with a hashed value
  # includes in FQDN. Possible values are NoReuse, ResourceGroupReuse, SubscriptionReuse and TenantReuse.

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

/*
resource "azurerm_monitor_diagnostic_setting" "pip-metrics" {
  count = var.vmss_number_of_instances == 0 || var.vmss_autoscale_enabled == false ? 0 : 1

  name                       = "Metrics-${azurerm_public_ip.nat[0].name}-to-Azure-Monitor"
  target_resource_id         = azurerm_public_ip.nat[0].id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
resource "azurerm_monitor_diagnostic_setting" "pip_logs" {
  count = var.vmss_number_of_instances == 0 || var.vmss_autoscale_enabled == false ? 0 : 1

  name                       = "Logs-${azurerm_public_ip.nat[0].name}-to-Azure-Monitor"
  target_resource_id         = azurerm_public_ip.nat[0].id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
}
*/

resource "azurerm_nat_gateway" "this" {
  count = var.vmss_number_of_instances == 0 || var.vmss_autoscale_enabled == false ? 0 : 1

  name                = "nat-${local.nat_name_location}"
  resource_group_name = azurerm_resource_group.environment.name
  location            = azurerm_resource_group.environment.location
  sku_name            = "StandardV2" ## There is no cost difference between the two SKUs. Standard and Standardv2 - StandardV2 is multi-zones for free
  tags                = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

resource "azurerm_nat_gateway_public_ip_association" "vnet-nat-gateway" {
  count = var.vmss_number_of_instances == 0 || var.vmss_autoscale_enabled == false ? 0 : 1

  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}
resource "azurerm_subnet_nat_gateway_association" "this" {
  count = var.vmss_number_of_instances == 0 || var.vmss_autoscale_enabled == false ? 0 : 1

  subnet_id      = local.vmss_subnet_id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}

/*
resource "azurerm_monitor_diagnostic_setting" "nat_gateway_metrics" {
  count = var.vmss_number_of_instances == 0 || var.vmss_autoscale_enabled == false ? 0 : 1

  name                       = "Metrics-${azurerm_nat_gateway.this[0].name}-to-Azure-Monitor"
  target_resource_id         = azurerm_nat_gateway.this[0].id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
resource "azurerm_monitor_diagnostic_setting" "nat_gateway_logs" {
  count = var.vmss_number_of_instances == 0 || var.vmss_autoscale_enabled == false ? 0 : 1

  name                       = "Logs-${azurerm_nat_gateway.this[0].name}-to-Azure-Monitor"
  target_resource_id         = azurerm_nat_gateway.this[0].id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
}
*/

module "vmss_keyvault" {
  source           = "Azure/avm-res-keyvault-vault/azurerm"
  version          = "~>0.7, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                            = local.vmss_name_hostname
  resource_group_name             = azurerm_resource_group.environment.name
  location                        = azurerm_resource_group.environment.location
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7
  public_network_access_enabled   = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true
  legacy_access_policies_enabled  = false
  enabled_for_deployment          = true ## Whether Azure Virtual Machines are permitted to retrieve certificates
  enabled_for_disk_encryption     = true ## Whether Azure Disk Encryption is permitted to retrieve secrets from the vault
  enabled_for_template_deployment = true ## Whether Azure Resource Manager is permitted to retrieve secrets from the vault
  network_acls = {
    default_action             = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? "Deny" : "Allow"
    bypass                     = "AzureServices"
    ip_rules                   = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? [] : ["0.0.0.0/0"]
    virtual_network_subnet_ids = [for subnets in azurerm_virtual_network.this.subnet : subnets.id if contains(subnets.service_endpoints, "Microsoft.KeyVault")]
  }

  /*
  diagnostic_settings = {
    diag_setting_1 = {
      name                           = "Logs-Metrics-And-Audit to Azure Monitor ${module.log_analytics_workspace.resource.name}"
      log_groups                     = ["allLogs", "audit"]
      metric_categories              = ["AllMetrics"]
      log_analytics_destination_type = null
      workspace_resource_id          = module.log_analytics_workspace.resource_id
    }
  }
*/
  role_assignments = {
    role_assignment_1 = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = azurerm_user_assigned_identity.environment.principal_id
      description                = local.iac_message
    }
    role_assignment_2 = {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = azurerm_user_assigned_identity.environment.principal_id
      description                = local.iac_message
    }
    role_assignment_3 = {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = data.azurerm_client_config.current.object_id
      description                = local.iac_message
    }
  }

  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
  depends_on = [
    azurerm_role_assignment.kvault_admin,
    azurerm_user_assigned_identity.environment
  ]
}

resource "random_string" "id" {
  length  = 55
  special = true
  upper   = true
  lower   = true
}

/*
module "avm_ptn_ephemeral_credential" {
  source  = "Azure/avm-ptn-ephemeral-credential/azure"
  version = "~>0.0, < 1.0"

  enable_telemetry = var.enable_telemetry
  password = {
    length      = 20
    special     = true
    upper       = true
    lower       = true
    numeric     = true
    min_lower   = 2
    min_upper   = 2
    min_numeric = 2
    min_special = 2
  }
  #retrievable_secret = {
  #  key_vault_id = azurerm_key_vault.vmss.id
  #  name         = "ephemeral-vm-password-${random_string.id.result}"
  #}
}

*/

#module "get_valid_sku_for_deployment_region" {
#  source = "../modules/sku_selector"
#
#  deployment_region = azurerm_resource_group.environment.location
#}

output "vmss_admin_username" {
  description = "The admin username for the VMSS."
  sensitive   = false
  value       = local.vmss_admin_username
}

output "vmss_admin_password_keyvault_id" {
  description = "The Key Vault ID where the VMSS admin password is stored."
  sensitive   = false
  value       = module.vmss_keyvault.resource_id
}

resource "azurerm_key_vault_secret" "vmss_admin_password" {
  key_vault_id = module.vmss_keyvault.resource_id
  name         = "VMSS-ADMIN-PASSWORD"
  value        = random_string.id.result
}
output "vmss_admin_password_keyvault_secret_name" {
  description = "The Key Vault secret name where the VMSS admin password is stored."
  sensitive   = false
  value       = azurerm_key_vault_secret.vmss_admin_password.name
}

##  source  = "Azure/avm-res-compute-virtualmachinescaleset/azurerm"
##  version          = "~>0.9, < 1.0"
##  enable_telemetry = var.enable_telemetry

module "virtualmachinescaleset" {
  source           = "Azure/avm-res-compute-virtualmachinescaleset/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                        = local.vmss_name
  parent_id                   = azurerm_resource_group.environment.id
  location                    = azurerm_resource_group.environment.location
  extension_protected_setting = {}
  user_data_base64            = null
  admin_password              = random_string.id.result
  admin_password_version      = random_string.id.result
  encryption_at_host_enabled  = true

  additional_capabilities = {
    ultra_ssd_enabled   = local.vmss_ultra_ssd_support
    hibernation_enabled = local.vmss_hibernate_enabled
  }

  managed_identities = {
    system_assigned = false
    user_assigned_resource_ids = [
      azurerm_user_assigned_identity.environment.id
    ]
  }

  priority        = local.vmss_spot_instances ? "Spot" : "Regular"
  max_bid_price   = local.vmss_spot_instances ? -1 : null
  eviction_policy = local.vmss_spot_instances ? "Deallocate" : null

  admin_ssh_keys = []
  automatic_instance_repair = {
    enabled      = true
    grace_period = "PT45M"
  }
  boot_diagnostics = {
    ## Enable boot diagnostics ( Managed storage )
  }
  custom_data         = base64encode(file("resource-vmss-init-script.ps1"))
  custom_data_version = "1"
  #data_disk = [{
  #  caching                   = "ReadWrite"
  #  create_option             = "Empty"
  #  disk_size_gb              = 10
  #  lun                       = 0
  #  managed_disk_type         = "StandardSSD_LRS"
  #  storage_account_type      = "StandardSSD_LRS"
  #  write_accelerator_enabled = false
  #}]
  extension = [
    {
      name                                      = "Execute.CustomData.bin"
      publisher                                 = "Microsoft.Compute"
      type                                      = "CustomScriptExtension"
      type_handler_version                      = "1.10"
      auto_upgrade_minor_version_enabled        = true
      failure_suppression_enabled               = false
      extensions_to_provision_after_vm_creation = []
      provision_after_extensions                = []
      settings = jsonencode({
        commandToExecute = "copy %SYSTEMDRIVE%\\AzureData\\CustomData.bin c:\\init-script.ps1 & powershell -ExecutionPolicy Unrestricted -File %SYSTEMDRIVE%\\init-script.ps1"
      })
    },
    /*
    ## need system-assigned identity for this extension to work, but VMSS Flexible does not support system-assigned identity; use user-assigned identity on the VMSS and a managed identity on the policy assignment if remediation is required.
    {
      name                                      = "AzurePolicyforWindows"
      publisher                                 = "Microsoft.GuestConfiguration"
      type                                      = "ConfigurationforWindows" ## VMSS Flexible does not support system-assigned identity; use user-assigned identity on the VMSS and a managed identity on the policy assignment if remediation is required.
      type_handler_version                      = "1.0"
      auto_upgrade_minor_version_enabled        = true
      failure_suppression_enabled               = false
      extensions_to_provision_after_vm_creation = []
      provision_after_extensions                = []
      settings = jsonencode({
        # No custom settings needed here — the extension itself just enables the
        # guest to receive Policy-driven machine configuration assignments.
      })
    },
    */
    {
      name                                      = "HealthExtension"
      publisher                                 = "Microsoft.ManagedServices"
      type                                      = "ApplicationHealthWindows"
      type_handler_version                      = "1.0"
      auto_upgrade_minor_version_enabled        = true
      failure_suppression_enabled               = false
      extensions_to_provision_after_vm_creation = []
      provision_after_extensions                = ["AdminCenter", "Execute.CustomData.bin"]
      settings                                  = "{\"port\":80,\"protocol\":\"http\",\"requestPath\":\"index.html\"}"
    },
    {
      name                                      = "AADLoginForWindows"
      publisher                                 = "Microsoft.Azure.ActiveDirectory"
      type                                      = "AADLoginForWindows"
      type_handler_version                      = "1.0"
      auto_upgrade_minor_version_enabled        = true
      failure_suppression_enabled               = false
      extensions_to_provision_after_vm_creation = []
      provision_after_extensions                = ["AADLoginForWindows"]
    },
    {
      name                                      = "NetworkWatcherAgent"
      publisher                                 = "Microsoft.Azure.NetworkWatcher"
      type                                      = "NetworkWatcherAgentWindows"
      type_handler_version                      = "1.4"
      auto_upgrade_minor_version_enabled        = true
      failure_suppression_enabled               = false
      extensions_to_provision_after_vm_creation = []
      provision_after_extensions                = ["AADLoginForWindows"]
    },
    {
      name                                      = "AzureMonitorWindowsAgent"
      publisher                                 = "Microsoft.Azure.Monitor"
      type                                      = "AzureMonitorWindowsAgent"
      type_handler_version                      = "1.0"
      auto_upgrade_minor_version_enabled        = true
      failure_suppression_enabled               = false
      extensions_to_provision_after_vm_creation = []
      provision_after_extensions                = ["AADLoginForWindows"]
      settings = jsonencode({
        authentication = {
          managedIdentity = {
            "identifier-name"  = azurerm_user_assigned_identity.environment.name
            "identifier-value" = azurerm_user_assigned_identity.environment.id
          }
        }
      })
    },
    {
      name                                      = "AdminCenter"
      publisher                                 = "Microsoft.AdminCenter"
      type                                      = "AdminCenter"
      type_handler_version                      = "0.0" # extension self-updates;
      auto_upgrade_minor_version_enabled        = true
      failure_suppression_enabled               = true
      extensions_to_provision_after_vm_creation = []
      provision_after_extensions                = ["AzureMonitorWindowsAgent"]
      settings = jsonencode({
        port = "6516"
        cspFrameAncestors = [
          "https://portal.azure.com",
          "https://*.hosting.portal.azure.net",
          "https://localhost:8443"
        ]
        corsOrigins = [
          "https://portal.azure.com",
          "https://localhost:8443"
        ]
      })
    },
    /*
    {
      name                                      = "ChangeTracking-Windows"
      publisher                                 = "Microsoft.Azure.ChangeTrackingAndInventory"
      type                                      = "ChangeTracking-Windows"
      type_handler_version                      = "2.20"
      auto_upgrade_minor_version_enabled        = true
      failure_suppression_enabled               = true
      extensions_to_provision_after_vm_creation = []
      provision_after_extensions                = ["AzureMonitorWindowsAgent"]
      settings = jsonencode({
        "workspaceId" = module.log_analytics_workspace.resource_id
      })
    }
*/
  ]
  instances           = local.vmss_number_of_instances
  license_type        = "Windows_Server"
  network_api_version = "2022-11-01" ##"2023-06-01"
  network_interface = [{
    name                      = "VMSS-NIC"
    network_security_group_id = azurerm_network_security_group.general.id
    ip_configuration = [{
      name      = "VMSS-IPConfig"
      subnet_id = local.vmss_subnet_id
      #public_ip_address = [{
      #  name     = "VMSS-PIP"
      #  sku_name = "StandardV2"
      #  sku_tier  = "Regional"
      #}]
      application_gateway_backend_address_pool_ids = var.inbound_access == "App-Gateway" ? "${azurerm_application_gateway.this[0].backend_address_pool[*].id}" : [] # (Optional) A set of Backend Address Pools IDs from a Application Gateway which this Orchestrated Virtual Machine Scale Set should be connected to.
      application_security_group_ids               = []                                                                                                             # (Optional) A set of Application Security Group IDs which this Orchestrated Virtual Machine Scale Set should be connected to.
      load_balancer_backend_address_pool_ids       = []                                                                                                             # (Optional) A set of Backend Address Pools IDs from a Load Balancer which this Orchestrated Virtual Machine Scale Set should be connected to. > Note: When using this field you'll also need to configure a Rule for the Load Balancer, and use a depends_on between this resource and the Load Balancer Rule.
    }]
    enable_accelerated_networking = local.vmss_accelerated_networking_enabled
    #domain_name_label                           = local.vmss_name_hostname
  }]
  os_profile = {
    windows_configuration = {
      admin_username                  = local.vmss_admin_username
      disable_password_authentication = false
      hotpatching_enabled             = true
      enable_automatic_updates        = true
      patch_mode                      = "AutomaticByPlatform"
      patch_assessment_mode           = local.vmss_patching_mode == "Manual" ? "ImageDefault" : "AutomaticByPlatform"
      timezone                        = local.regions[azurerm_resource_group.environment.location].timezone
      provision_vm_agent              = true
      winrm_listener = [{
        protocol = "Http"
      }]
    }
  }
  proxy_agent_settings = {
    enabled = true
    #add_proxy_agent_extension = true ## this happens automatically on Windows
    imds = {
      mode = "Audit"
    }
    wire_server = {
      mode = "Audit"
    }
  }

  role_assignments = {
    role_assignment_1 = {
      role_definition_id_or_name = "Windows Admin Center Administrator Login"
      principal_id               = var.owner_entra_object_id
      description                = local.iac_message
    }
    role_assignment_2 = {
      role_definition_id_or_name = "Virtual Machine Administrator Login"
      principal_id               = var.owner_entra_object_id
      description                = local.iac_message
    }
    role_assignment_3 = {
      role_definition_id_or_name = "Essential Machine Management Administrator"
      principal_id               = var.owner_entra_object_id
      description                = local.iac_message
    }
  }

  upgrade_policy = {
    upgrade_mode = local.vmss_patching_mode == "Manual" ? "Manual" : "Rolling"
    rolling_upgrade_policy = {
      prioritize_unhealthy_instances_enabled  = true
      cross_zone_upgrades_enabled             = true
      maximum_surge_instances_enabled         = true
      max_batch_instance_percent              = 30
      max_unhealthy_instance_percent          = 20
      max_unhealthy_upgraded_instance_percent = 20
      pause_time_between_batches              = "PT20M"
    }
  }
  os_disk = {
    caching                   = "ReadOnly"
    storage_account_type      = "StandardSSD_LRS"
    disk_size_gb              = 127
    write_accelerator_enabled = false
    placement                 = "ResourceDisk"
    #disk_encryption_set_id = azurerm_disk_encryption_set.this.id
  }
  disk_controller_type = var.vmss_disk_controller_type ## Possible values are 'SCSI' and 'NVMe'. Defaults to 'SCSI'.
  sku_name             = var.vmss_sku_name != "" ? var.vmss_sku_name : local.virtual_machine_x64_random
  ## az vm image list --publisher MicrosoftWindowsServer --offer WindowsServer --sku 2025 --all
  ## note, that core edition does not support defender, the logon extension, and the admin center extension, so we use the full edition.
  source_image_reference = { ## this SKU supports hibernation
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-azure-edition-smalldisk"
    version   = "latest"
  }

  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
  depends_on = [
    module.vm_x64_skus,
    azurerm_user_assigned_identity.environment
  ]
}

module "vmss_autoscale_setting" {
  count = var.vmss_autoscale_enabled ? 1 : 0

  source           = "Azure/avm-res-insights-autoscalesetting/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                = "${local.vmss_name}-autoscale"
  resource_group_name = azurerm_resource_group.environment.name
  location            = azurerm_resource_group.environment.location
  target_resource_id  = module.virtualmachinescaleset.resource_id
  enabled             = true

  predictive = {
    scale_mode      = "Enabled"
    look_ahead_time = var.vmss_autoscale_predictive_look_ahead_time
  }

  profiles = {
    business_hours = {
      name = "business-hours"
      capacity = {
        default = var.vmss_autoscale_default_capacity
        minimum = var.vmss_autoscale_min_capacity
        maximum = var.vmss_autoscale_max_capacity
      }
      rules = {
        cpu_scale_out = {
          metric_trigger = {
            metric_name        = "Percentage CPU"
            metric_resource_id = module.virtualmachinescaleset.resource_id
            metric_namespace   = "microsoft.compute/virtualmachinescalesets"
            time_grain         = var.vmss_autoscale_time_grain
            statistic          = "Average"
            time_window        = var.vmss_autoscale_time_window
            time_aggregation   = "Average"
            operator           = "GreaterThan"
            threshold          = var.vmss_autoscale_scale_out_cpu_threshold
          }
          scale_action = {
            direction = "Increase"
            type      = "ChangeCount"
            value     = tostring(var.vmss_autoscale_scale_out_increase_count)
            cooldown  = var.vmss_autoscale_cooldown
          }
        }
      }
      # Was the non-recurring "default" profile — that's exactly what triggered the "no end
      # time" warning: with two other profiles recurring perpetually (one on all 7 days), a
      # non-scheduled profile can never actually become active, so Azure disables it. Giving
      # this profile its own weekday-morning trigger makes all three profiles unambiguous.
      recurrence = {
        timezone = local.regions[azurerm_resource_group.environment.location].timezone
        days     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        hours    = [var.vmss_autoscale_business_hours_start]
        minutes  = [0]
      }
    }
    weekend = {
      name = "weekend"
      capacity = {
        default = var.vmss_autoscale_weekend_capacity
        minimum = var.vmss_autoscale_weekend_capacity
        maximum = var.vmss_autoscale_weekend_capacity
      }
      recurrence = {
        timezone = local.regions[azurerm_resource_group.environment.location].timezone
        days     = ["Saturday", "Sunday"]
        hours    = [0]
        minutes  = [0]
      }
    }
    zero = {
      name = "zero"
      capacity = {
        default = 0
        minimum = 0
        maximum = 0
      }
      # Weekdays only — Sat/Sun overnight is already covered by the "weekend" profile's
      # floor, so "zero" no longer needs to (and shouldn't) fire on those days too.
      recurrence = {
        timezone = local.regions[azurerm_resource_group.environment.location].timezone
        days     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        hours    = [17]
        minutes  = [10]
      }
    }
  }

  notification = {
    email = {
      send_to_subscription_administrator    = false
      send_to_subscription_co_administrator = false
      #custom_emails                         = [var.alert_email, var.owner_email]
    }
  }
  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

/*
resource "azapi_resource_action" "create_shareable_link" {
  for_each = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? { for id in local.vmss_instance_virtual_machine_ids : id => id } : {}

  when        = "apply"
  type        = "Microsoft.Network/bastionHosts@2025-07-01"
  resource_id = azurerm_bastion_host.this.id
  action      = "createShareableLinks"
  body = {
    vms = [
      {
        vm = {
          id = each.value
        }
      }
    ]
  }
}
resource "azapi_resource_action" "delete_shareable_link" {
  for_each = var.bastion_sku == "Standard" || var.bastion_sku == "Premium" ? tomap(local.vmss_instance_virtual_machine_ids) : {}

  when        = "destroy"
  type        = "Microsoft.Network/bastionHosts@2025-07-01"
  resource_id = azurerm_bastion_host.this.id
  action      = "deleteShareableLinks"
  body = {
    vms = [
      {
        vm = {
          id = each.value
        }
      }
    ]
  }
}
*/

/*
data "azapi_resource_action" "test" {
  type                   = "Microsoft.Network/bastionHosts@2022-05-01"
  resource_id            = "/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Network/bastionHosts/{bastionHostName}"
  action                 = "getShareableLinks"
  response_export_values = ["*"]
}
*/

#resource "azapi_update_resource" "enable_hibernation" {
#  count = local.vmss_hibernate_enabled ? 1 : 0
#
#  type        = "Microsoft.Compute/virtualMachineScaleSets@2024-07-01"
#  resource_id = module.virtualmachinescaleset.resource_id
#
##  body = {
##    properties = {
##      additionalCapabilities = {
##        hibernationEnabled = true
##      }
##    }
##  }
##  depends_on = [
##    module.virtualmachinescaleset.resource_id,
##  ]
##}

## https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/standby-pools-configure-permissions
## Standby Pool Resource Provider
resource "azurerm_role_assignment" "standby_pool_permission1" {
  count = local.vmss_enable_standby_pool ? 1 : 0

  scope                = azurerm_resource_group.environment.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = "05482a4e-4826-4fa3-8276-a8f74baccbe0" ## Standby Pool Resource Provider
  description          = local.iac_message
}
resource "azurerm_role_assignment" "standby_pool_permission2" {
  count = local.vmss_enable_standby_pool ? 1 : 0

  scope                = azurerm_resource_group.environment.id
  role_definition_name = "Network Contributor"
  principal_id         = "05482a4e-4826-4fa3-8276-a8f74baccbe0" ## Standby Pool Resource Provider
  description          = local.iac_message
}
resource "azurerm_role_assignment" "standby_pool_permission3" {
  count = local.vmss_enable_standby_pool ? 1 : 0

  scope                = azurerm_resource_group.environment.id
  role_definition_name = "Managed Identity Contributor"
  principal_id         = "05482a4e-4826-4fa3-8276-a8f74baccbe0" ## Standby Pool Resource Provider
  description          = local.iac_message
}
resource "azurerm_role_assignment" "standby_pool_permission4" {
  count = local.vmss_enable_standby_pool ? 1 : 0

  scope                = azurerm_resource_group.environment.id
  role_definition_name = "Compute Gallery Sharing Admin"
  principal_id         = "05482a4e-4826-4fa3-8276-a8f74baccbe0" ## Standby Pool Resource Provider
  description          = local.iac_message
}
resource "azurerm_role_assignment" "standby_pool_permission5" {
  count = local.vmss_enable_standby_pool ? 1 : 0

  scope                = azurerm_resource_group.environment.id
  role_definition_name = "Compute Gallery Artifacts Publisher"
  principal_id         = "05482a4e-4826-4fa3-8276-a8f74baccbe0" ## Standby Pool Resource Provider
  description          = local.iac_message
}

resource "azurerm_role_assignment" "compute_recommendations" {
  scope                = azurerm_resource_group.environment.id
  role_definition_name = "Compute Diagnostics Role"
  principal_id         = "089139a2-afde-492b-9ffb-85096212422d" ## Compute Recommendation Service
  description          = local.iac_message
}

## The VMSS must be hibernation enabled
resource "azurerm_virtual_machine_scale_set_standby_pool" "hibernated" {
  count = local.vmss_enable_standby_pool ? 1 : 0

  name                                  = "${local.vmss_name}-hibernated-pool"
  resource_group_name                   = azurerm_resource_group.environment.name
  location                              = azurerm_resource_group.environment.location
  attached_virtual_machine_scale_set_id = module.virtualmachinescaleset.resource_id
  virtual_machine_state                 = "Hibernated"

  elasticity_profile {
    max_ready_capacity = 3 ## Specifies the maximum number of virtual machines in the standby pool.
    min_ready_capacity = 1 ## Specifies the desired minimum number of virtual machines in the standby pool.
  }

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
  depends_on = [
    module.virtualmachinescaleset.resource_id,
    azurerm_role_assignment.standby_pool_permission1,
    azurerm_role_assignment.standby_pool_permission2,
    azurerm_role_assignment.standby_pool_permission3,
    azurerm_role_assignment.standby_pool_permission4,
    azurerm_role_assignment.standby_pool_permission5,
  ]
}


/*
resource "azurerm_network_connection_monitor" "this" {
  count = var.vmss_number_of_instances == 0 ? 0 : 1

  name               = "cm-vmss-to-external"
  network_watcher_id = data.azurerm_network_watcher.this.id
  location           = data.azurerm_network_watcher.this.location

  endpoint {
    name               = "vmss-source"
    target_resource_id = module.virtualmachinescaleset.resource_id
  }

  endpoint {
    name    = "external-destination1"
    address = "cnn.com"
  }

  test_configuration {
    name                      = "tcp-443"
    protocol                  = "Tcp"
    test_frequency_in_seconds = 60 ## 600

    tcp_configuration {
      port                = 443
      trace_route_enabled = true
    }

    success_threshold {
      checks_failed_percent = 20
      round_trip_time_ms    = 1000
    }
  }

  test_group {
    name                     = "vmss-to-external"
    destination_endpoints    = ["external-destination1"]
    source_endpoints         = ["vmss-source"]
    test_configuration_names = ["tcp-443"]
    enabled                  = true
  }
  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }

  depends_on = [
    module.virtualmachinescaleset
  ]
}
*/
