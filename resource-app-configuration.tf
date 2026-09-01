locals {
  appconfiguration_sku               = "free" ## "standard" is the default/null,  options are: free, developer, standard, and premium
  appconfiguration_env_name          = "app-configuration-${local.appconfiguration_sku}-${var.prefix}"
  appconfiguration_env_name_location = lower("${local.appconfiguration_env_name}-${lower(var.location)}")
  appconfiguration_env_random_suffix = substr(md5(local.appconfiguration_env_name_location), 0, 6)
  appconfiguration_env_name_hostname = lower(substr(replace("f${local.appconfiguration_env_random_suffix}${local.appconfiguration_env_name_location}", "-", ""), 0, 24))
}

#data "azuread_service_principal" "cert_spn" {
#  display_name = "f3c21649-0979-4721-ac85-b0216b2cf413" ## "Microsoft.Azure.CertificateRegistration"
#}

module "appconfiguration" {
  source           = "Azure/avm-res-appconfiguration-configurationstore/azure"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry ## see variables.tf

  name                            = local.appconfiguration_env_name_location
  location                        = module.environment_resource_group.resource.location
  resource_group_resource_id      = module.environment_resource_group.resource_id
  azapi_schema_validation_enabled = false
  sku                             = local.appconfiguration_sku
  public_network_access_enabled   = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true
  soft_delete_retention_days      = local.appconfiguration_sku == "free" ? null : 7
  purge_protection_enabled        = local.appconfiguration_sku == "free" ? false : true

  managed_identities = {
    system_assigned = false
    user_assigned_resource_ids = [
      azurerm_user_assigned_identity.environment.id
    ]
  }

  /*
  diagnostic_settings = {
    diag_setting_1 = {
      name                           = "Logs-Metrics-And-Audit-to-Azure-Monitor-${module.log_analytics_workspace.resource.name}"
      log_groups                     = ["allLogs", "audit"]
      metric_categories              = ["AllMetrics"]
      log_analytics_destination_type = null
      workspace_resource_id          = module.log_analytics_workspace.resource_id
    }
  }
*/

  key_values = {
    SQL_DATABASE_CONNECTION_STRING = {
      key   = "SQL_DATABASE_CONNECTION_STRING"
      label = "basic"
      value = local.sql_database_connection_free_encrypted
    }
    CUSTOMER = {
      key   = upper("customer")
      label = "basic"
      value = var.customer
    }
    PREFIX = {

      key   = upper("prefix")
      label = "basic"
      value = var.prefix
    }
    LOCATION = {

      key   = upper("location")
      label = "basic"
      value = var.location
    }
    SUBSCRIPTION_ID = {

      key   = upper("subscription-id")
      label = "basic"
      value = var.subscription_id
    }
    OWNER = {
      key   = upper("owner")
      label = "basic"
      value = var.owner_email
    }
  }

  role_assignments = {
    role_assignment_1 = {
      role_definition_id_or_name       = "App Configuration Data Reader"
      principal_id                     = azurerm_user_assigned_identity.environment.principal_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    role_assignment_2 = {
      role_definition_id_or_name       = "App Configuration Reader"
      principal_id                     = azurerm_user_assigned_identity.environment.principal_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    role_assignment_4 = {
      role_definition_id_or_name       = "Owner"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
  }

  replicas = contains(["standard", "premium"], local.appconfiguration_sku) ? {
    replica_1 = {
      name     = "replica-1"
      location = local.regions[module.environment_resource_group.resource.location].default_rep_location
    }
  } : null

  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  depends_on = [
    azurerm_user_assigned_identity.environment,
  ]
}

locals {
  feature_test_feature = {
    name        = "TestFeature"
    label       = "TestFeature"
    description = "Enable this new TestFeature feature"
  }
}
resource "azurerm_app_configuration_feature" "test_feature" {
  configuration_store_id = module.appconfiguration.resource_id

  name        = local.feature_test_feature.name
  label       = local.feature_test_feature.label
  description = local.feature_test_feature.description
  enabled     = true
  locked      = false
  tags        = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

resource "azapi_update_resource" "configurationStore_telemetry" {
  type        = "Microsoft.AppConfiguration/configurationStores@2025-08-01-preview"
  resource_id = module.appconfiguration.resource_id
  body = {
    properties = {
      telemetry = {
        resourceId = module.application_insights.resource_id
      }
    }
  }
  response_export_values = ["*"]
  depends_on = [
    module.application_insights,
    module.appconfiguration,
  ]
}

output "appconfiguration_name" {
  description = "The name of the environment's Azure App Configuration store."
  sensitive   = false
  value       = module.appconfiguration.name
}

output "appconfiguration_id" {
  description = "The resource ID of the environment's Azure App Configuration store."
  sensitive   = false
  value       = module.appconfiguration.resource_id
}

output "appconfiguration_endpoint" {
  description = "The endpoint of the environment's Azure App Configuration store."
  sensitive   = false
  value       = module.appconfiguration.endpoint
}

output "appconfiguration_replica_resource_ids" {
  description = "The resource IDs of the environment's Azure App Configuration store replicas."
  sensitive   = false
  value       = module.appconfiguration.replica_resource_ids
}

/*
output "appconfiguration_sku" {
  description = "The SKU of the environment's Azure App Configuration store."
  sensitive   = false
  value       = module.appconfiguration.sku
}
*/
