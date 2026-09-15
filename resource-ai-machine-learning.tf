locals {
  ml_name          = "mlhub-${var.prefix}"
  ml_name_location = lower("${local.ml_name}-${lower(var.location)}")
  ml_random_suffix = substr(random_string.environment.result, 0, 6)
  ml_name_hostname = lower(substr(replace("c${local.ml_random_suffix}${var.prefix}${local.ml_name_location}", "-", ""), 0, 24))
  ml_scenario      = "AI Hub and Projects"
}

module "aihub" {
  source           = "Azure/avm-res-machinelearningservices-workspace/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                = local.ml_name
  location            = module.environment_resource_group.resource.location
  resource_group_name = module.environment_resource_group.resource.name
  key_vault = {
    resource_id = module.ai_keyvault.resource_id
  }
  kind = "Hub" ## offering additional AI capabilities while still leveraging the underlying
  ## Azure Machine Learning infrastructure.
  provision_network_now_enabled = false
  public_network_access_enabled = true
  storage_account = {
    resource_id = azurerm_storage_account.this.id
  }
  workspace_friendly_name = "AI Studio Hub"
  workspace_managed_network = {
    isolation_mode = "Disabled"
    spark_ready    = false
  }
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
