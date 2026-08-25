locals {
  foundry_friendly_name      = "Azure AI Foundry"
  foundry_name               = "foundry-${var.prefix}"
  foundry_name_location      = lower("${local.foundry_name}-${lower(var.location)}")
  foundry_name_random_suffix = substr(md5(local.foundry_name_location), 0, 6)
  foundry_name_hostname      = lower(substr(replace("w${local.foundry_name_random_suffix}${local.foundry_name_location}", "-", ""), 0, 24))
}

module "foundry_keyvault" {
  source           = "Azure/avm-res-keyvault-vault/azurerm"
  version          = "~>0.7, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                            = local.foundry_name_hostname
  resource_group_name             = module.environment_resource_group.resource.name
  location                        = module.environment_resource_group.resource.location
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7
  public_network_access_enabled   = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true
  legacy_access_policies_enabled  = false
  enabled_for_deployment          = false ## Whether Azure Virtual Machines are permitted to retrieve certificates
  enabled_for_disk_encryption     = false ## Whether Azure Disk Encryption is permitted to retrieve secrets from the vault
  enabled_for_template_deployment = false ## Whether Azure Resource Manager is permitted to retrieve secrets from the vault
  network_acls = {
    default_action             = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? "Deny" : "Allow"
    bypass                     = "AzureServices"
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
    role_assignment_4 = {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azurerm_client_config.current.object_id
      description                = local.iac_message
    }
  }
  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  depends_on = [
    azurerm_user_assigned_identity.environment
  ]
}


/*
module "avm-res-cognitiveservices-account" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.11.1"

  # insert the 5 required variables here
}
*/

resource "azapi_resource" "foundry" {
  type      = "Microsoft.CognitiveServices/accounts@2026-05-15-preview"
  name      = local.foundry_name_hostname
  parent_id = module.environment_resource_group.resource_id
  location  = module.environment_resource_group.resource.location

  schema_validation_enabled = true

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }

  body = {
    kind = "AIServices"

    sku = {
      name = "S0"
    }

    properties = {
      allowProjectManagement        = true
      customSubDomainName           = local.foundry_name_hostname
      disableLocalAuth              = true
      dynamicThrottlingEnabled      = true
      publicNetworkAccess           = "Enabled"
      restrictOutboundNetworkAccess = false
      #restore                       = true
    }
  }

  response_export_values = [
    "identity.principalId",
    "properties.endpoint"
  ]

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

/*
resource "azurerm_monitor_diagnostic_setting" "foundry_logging" {
  name                       = "Audit-Metrics-and-Logs-${azapi_resource.foundry.name}-to-Azure-Monitor"
  target_resource_id         = azapi_resource.foundry.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "audit"
  }
  enabled_log {
    category_group = "allLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}
*/

resource "azapi_resource" "default_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = "proj-${local.foundry_name}"
  parent_id = azapi_resource.foundry.id
  location  = var.location

  schema_validation_enabled = false

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }

  body = {
    properties = {
      displayName  = "Default Project"
      friendlyName = "Friendly Default Project"
      description  = "Terraform managed Microsoft Foundry project"
    }
  }

  response_export_values = [
    "identity.principalId"
  ]

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

/*
resource "azurerm_monitor_diagnostic_setting" "foundry_project_audit" {
  name                       = "Audit-and-Logs-${azapi_resource.default_project.name}-to-Azure-Monitor"
  target_resource_id         = azapi_resource.default_project.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "audit"
  }
  enabled_log {
    category_group = "allLogs"
  }
}
*/

/*
resource "azurerm_monitor_diagnostic_setting" "foundry_project_metrics" {
  name                       = "Metrics-${azapi_resource.default_project.name}-to-Azure-Monitor"
  target_resource_id         = azapi_resource.default_project.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
*/

locals {
  foundry_principal_id = azurerm_user_assigned_identity.environment.principal_id
  project_principal_id = azurerm_user_assigned_identity.environment.principal_id
  foundry_endpoint     = azapi_resource.foundry.output.properties.endpoint
}

resource "azurerm_role_assignment" "project_storage_blob_data_contributor" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.project_principal_id
  description          = local.iac_message
}

/*
data "azapi_resource_action" "model_capacities" {
  type        = "Microsoft.CognitiveServices/locations@2025-06-01"
  resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}/providers/Microsoft.CognitiveServices/locations/${var.location}"

  action = "modelCapacities"
  method = "GET"
  query_parameters = {
    modelFormat = ["OpenAI"]
  }
  response_export_values    = ["*"]
  ignore_not_found          = true
  schema_validation_enabled = false
  when                      = ["apply"]
}
*/

resource "azapi_resource" "embedding_small" {
  count = var.deploy_ai_embeddings ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/deployments@2023-05-01"
  name      = "text-embedding-3-small"
  parent_id = azapi_resource.foundry.id

  body = {
    sku = {
      name     = "GlobalStandard"
      capacity = 1
    }

    properties = {
      model = {
        format  = "OpenAI"
        name    = "text-embedding-3-small"
        version = "1"
      }
    }
  }
}

resource "azapi_resource" "embedding_gpt4o" {
  count = var.deploy_ai_embeddings ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/deployments@2023-05-01"
  name      = "gpt-4o"
  parent_id = azapi_resource.foundry.id

  body = {
    sku = {
      name     = "GlobalStandard"
      capacity = 1
    }

    properties = {
      model = {
        format  = "OpenAI"
        name    = "gpt-4o"
        version = "2024-11-20"
      }
    }
  }
}

output "foundry_name" {
  description = "The name of the Foundry resource."
  sensitive   = false
  value       = try(azapi_resource.foundry.name, null)
}

output "foundry_principal_id" {
  description = "The principal ID of the Foundry resource, used for role assignments."
  sensitive   = false
  value       = try(local.foundry_principal_id, null)
}

output "foundry_endpoint" {
  description = "The endpoint of the Foundry resource."
  sensitive   = false
  value       = try(local.foundry_endpoint, null)
}
