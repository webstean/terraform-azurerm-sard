locals {
  ml_name          = "mlhub-${var.prefix}"
  ml_name_location = lower("${local.ml_name}-${lower(var.location)}")
  ml_random_suffix = substr(random_string.environment.result, 0, 6)
  ml_name_hostname = lower(substr(replace("c${local.ml_random_suffix}${var.prefix}${local.ml_name_location}", "-", ""), 0, 24))
  ml_scenario      = "AI Hub and Projects"
}

resource "azurerm_subnet" "mlhub" {
  count = var.deploy_private_endpoints ? 1 : 0

  name                 = "machine-learning"
  resource_group_name  = module.environment_resource_group.resource.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [format("10.%s.92.0/24", local.regions[var.location].location_number)]
  ## Note, the VMSS won't use the default Internet outbound (even if enabled - you have to use a NAT Gateway)
  default_outbound_access_enabled               = var.deploy_private_endpoints ? false : true
  service_endpoints                             = var.deploy_private_endpoints ? null : local.service_endpoints
  private_link_service_network_policies_enabled = false
  ## Possible values are Disabled, Enabled, NetworkSecurityGroupEnabled and RouteTableEnabled.
  private_endpoint_network_policies = "Enabled"
  #service_endpoint_policy_ids = [
  #  azurerm_subnet_service_endpoint_storage_policy.storage.id
  #]
  depends_on = [
    azurerm_virtual_network.this
  ]
}

module "aihub" {
  source           = "Azure/avm-res-machinelearningservices-workspace/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                = local.ml_name
  location            = module.environment_resource_group.resource.location
  resource_group_name = module.environment_resource_group.resource.name
  hbi_workspace       = (tobool(var.data_pii) || tobool(var.data_phi)) ? true : false
  managed_identities = {
    system_assigned = false
    user_assigned_resource_ids = [
      azurerm_user_assigned_identity.environment.id
    ]
  }
  primary_user_assigned_identity = {
    resource_id = azurerm_user_assigned_identity.environment.id
  }
  key_vault = {
    resource_id = module.ai_keyvault.resource_id
  }
  kind = "Hub" ## offering additional AI capabilities while still leveraging the underlying
  ## Azure Machine Learning infrastructure.
  provision_network_now_enabled = false
  public_network_access_enabled = true
  application_insights = {
    resource_id = module.application_insights.resource_id
  }
  storage_account = {
    resource_id = azurerm_storage_account.this.id
  }
  azure_ai_hub = {
    description = "An offering additional AI capabilities while still leveraging the underlying Azure Machine Learning infrastructure."
  }
  container_registry = {
    resource_id = var.container_registry_id
  }
  workspace_description   = "An offering additional AI capabilities while still leveraging the underlying Azure Machine Learning infrastructure."
  workspace_friendly_name = "AI Studio Hub"
  workspace_managed_network = {
    isolation_mode = "Disabled"
    spark_ready    = false
  }
  role_assignments = {
    sp_role_assignment_1 = {
      name                             = uuidv5("url", "${module.environment_resource_group.resource.id}/Cognitive Services OpenAI User/${azurerm_user_assigned_identity.environment.principal_id}")
      role_definition_id_or_name       = "Cognitive Services OpenAI User"
      principal_id                     = azurerm_user_assigned_identity.environment.principal_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    up_role_assignment_1 = {
      name                             = uuidv5("url", "${module.environment_resource_group.resource.id}/Cognitive Services OpenAI User/${azurerm_user_assigned_identity.environment.principal_id}")
      role_definition_id_or_name       = "Cognitive Services OpenAI User"
      principal_id                     = var.owner_entra_object_id
      skip_service_principal_aad_check = false
      principal_type                   = "User"
      description                      = local.iac_message
    }
  }
  serverless_compute = var.deploy_private_endpoints ? {
    subnet_id = azurerm_subnet.mlhub[0].id
  } : null
  lock = (tobool(var.data_pii) || tobool(var.data_phi)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  depends_on = [
    azurerm_user_assigned_identity.environment,
  ]
}

resource "azapi_resource" "aiservices_connection" {
  name      = "scconnection"
  parent_id = module.aihub.resource_id
  type      = "Microsoft.MachineLearningServices/workspaces/connections@2025-07-01-preview"
  body = {
    properties = {
      category      = "AIServices"
      target        = azapi_resource.foundry.id
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure",
        ResourceId = azapi_resource.foundry.id
      }
    }
  }
}

output "ai_hub_id" {
  description = "The resource ID of the AI Hub."
  sensitive   = false
  value       = module.aihub.resource_id
}
