locals {
  environment_name          = "env-${var.prefix}"
  environment_name_location = lower("${local.environment_name}-${lower(var.location)}")
  environment_random_suffix = substr(md5(local.environment_name_location), 0, 6)
  environment_name_hostname = lower(substr(replace("c${local.environment_random_suffix}${local.environment_name_location}", "-", ""), 0, 24))
  environment_home_page     = "www.webstean.com"
  portal_link               = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/rg-${local.environment_name_location}/overview"
}

module "environment_resource_group" {
  source           = "Azure/avm-res-resources-resourcegroup/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry

  name     = "rg-${lower(local.environment_name_location)}"
  location = var.location
  role_assignments = {
    ## ==========================================================================================
    "sp_roleassignment1" = {
      role_definition_id_or_name       = "Contributor"
      principal_id                     = azurerm_user_assigned_identity.environment.principal_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment2" = {
      role_definition_id_or_name       = "User Access Administrator"
      principal_id                     = azurerm_user_assigned_identity.environment.principal_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment3" = {
      role_definition_id_or_name       = "Key Vault Administrator"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment4" = {
      role_definition_id_or_name       = "Storage Blob Data Owner"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment5" = {
      role_definition_id_or_name       = "Storage Queue Data Contributor"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment6" = {
      role_definition_id_or_name       = "Storage Table Data Contributor"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment7" = {
      role_definition_id_or_name       = "Storage File Data Privileged Contributor"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment8" = {
      role_definition_id_or_name       = "App Configuration Data Owner"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    ## ==========================================================================================
    "up_roleassignment1" = {
      role_definition_id_or_name       = "Contributor"
      principal_id                     = var.owner_entra_object_id
      skip_service_principal_aad_check = false
      principal_type                   = "User"
      description                      = local.iac_message
    }
    "up_roleassignment2" = {
      role_definition_id_or_name       = "Reader and Data Access" ## Storage Only
      principal_id                     = var.owner_entra_object_id
      skip_service_principal_aad_check = false
      principal_type                   = "User"
      description                      = local.iac_message
    }
    /*
    "up_roleassignment3" = {
      role_definition_id_or_name       = "Storage Blob Data Reader"
      principal_id                     = var.owner_entra_object_id
      skip_service_principal_aad_check = false
      principal_type                   = "User"
      description                      = local.iac_message
      # ABAC condition version 2.0 is required for blob index tag conditions
      condition_version = "2.0"

      condition = <<-CONDITION
    (
      (
        !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'})
      )
      OR
      (
        @Resource[Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags:createdby<$key_case_sensitive$>] StringEquals 'Terraform'
      )
    )
  CONDITION
    },
*/
  }
  retry = {
    error_message_regex  = [".*"]
    interval_seconds     = 5
    max_interval_seconds = 60
  }
  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags = merge(local.temporary_tags, {
    type = "permanent"
  })
}

# Wait 10 seconds for the network watcher to be created as a byproduct of the VNet creation
resource "time_sleep" "wait_10_seconds_for_network_watcher_creation" {
  create_duration = "10s"

  depends_on = [azurerm_virtual_network.this]
}

# Network Watcher — one per region per subscription is the norm; Azure will reject a
# duplicate if one already exists in this region, so remove/import this resource if so.
data "azurerm_network_watcher" "this" {
  name                = "NetworkWatcher_${lower(var.location)}"
  resource_group_name = "NetworkWatcherRG"
  depends_on          = [azurerm_virtual_network.this]
}

output "environment_resource_group_name" {
  description = "The Azure Resource Group that contains this environment"
  sensitive   = false
  value       = module.environment_resource_group.resource.name
}
output "environment_resource_group_location" {
  description = "The Azure Resource Group that contains this environment"
  sensitive   = false
  value       = var.location
}

output "security_perimeter_inbound_public_ips" {
  type        = list(string)
  description = "List of public IPs allowed for inbound traffic to the security perimeter"
  sensitive   = false
  value       = var.security_perimeter_inbound_public_ips
}

output "security_perimeter_outbound_fqdns" {
  type        = list(string)
  description = "List of FQDNs allowed for outbound traffic from the security perimeter"
  sensitive   = false
  value       = var.security_perimeter_outbound_fqdns
}

resource "azurerm_user_assigned_identity" "environment" {
  name = "id-${local.environment_name_location}"

  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location
  isolation_scope     = "Regional"
  tags                = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}
resource "time_sleep" "environment_identity_create_wait" {
  create_duration = "1m"
  depends_on      = [azurerm_user_assigned_identity.environment]
}
## https://learn.microsoft.com/en-us/azure/operations/configuration-enrollment#managed-identity

output "subscription_display_name" {
  description = "The subscription display name of the current Azure subscription."
  sensitive   = false
  value       = try(data.azurerm_subscription.current.display_name, null)
}

output "subscription_id" {
  description = "The subscription ID of the current Azure subscription."
  sensitive   = false
  value       = try(data.azurerm_subscription.current.subscription_id, null)
}

