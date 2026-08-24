locals {
  cosmos_name          = "cosmos-${var.prefix}"
  cosmos_name_location = lower("${local.cosmos_name}-${lower(var.location)}")
  cosmos_random_suffix = substr(md5(local.cosmos_name_location), 0, 6)
  cosmos_name_hostname = lower(substr(replace("cc${local.cosmos_random_suffix}${local.cosmos_name_location}", "-", ""), 0, 24))
}

module "cosmos" {
  source           = "Azure/avm-res-documentdb-databaseaccount/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                = local.cosmos_name_location
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location

  managed_identities = {
    system_assigned = false
    user_assigned_resource_ids = [
      azurerm_user_assigned_identity.environment.id
    ]
  }
  access_key_metadata_writes_enabled = true
  automatic_failover_enabled         = false

  /*
  diagnostic_settings = {
    diag_setting_1 = {
      name                           = "Audit-Metrics-and-Logs-${module.cosmos.name}-to-Azure-Monitor"
      log_groups                     = ["audit", "allLogs"]
      metric_categories              = ["SLI", "Requests"]
      log_analytics_destination_type = null
      workspace_resource_id          = module.log_analytics_workspace.resource_id
    }
    #diag_setting_2 = {
    #  name                  = "Minimal-Metrics-${module.cosmos.name}-to-Azure-Monitor"
    #  workspace_resource_id = module.log_analytics_workspace.resource_id
    #  metric_categories     = ["SLI", "Requests"]
    #}
  }
*/

  free_tier_enabled                     = true
  public_network_access_enabled         = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : false # must be false at Unisys, due to policy
  local_authentication_disabled         = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true  # must be false at Unisys, due to policy
  network_acl_bypass_for_azure_services = true
  multiple_write_locations_enabled      = false
  partition_merge_enabled               = false

  capabilities = [
    {
      name = "DeleteAllItemsByPartitionKey"
    }
  ]
  consistency_policy = {
    consistency_level       = "Session"
    max_interval_in_seconds = 5
    max_staleness_prefix    = 100
  }
  virtual_network_rules = []

  role_assignments = {
    role_assignment_1 = {
      role_definition_id_or_name = "Cosmos DB Account Reader Role"
      principal_id               = azurerm_user_assigned_identity.environment.principal_id
      description                = local.iac_message
    }
  }

  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

## 'Cosmos DB Built-in Data Contributor' is an Azure Cosmos DB data-plane role (Microsoft.DocumentDB)
resource "azurerm_cosmosdb_sql_role_assignment" "this" {
  resource_group_name = module.environment_resource_group.resource.name
  account_name        = module.cosmos.name

  role_definition_id = "${module.cosmos.resource_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"

  principal_id = azurerm_user_assigned_identity.environment.principal_id

  scope = module.cosmos.resource_id
}

