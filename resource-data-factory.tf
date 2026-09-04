locals {
  adf_friendly_name       = "Azure Data Factory"
  adf_name                = "adf-${var.prefix}"
  adf_name_location       = "${local.adf_name}-${lower(var.location)}"
  adf_name_random_suffix  = substr(md5(local.adf_name_location), 0, 6)
  adf_name_hostname       = lower(substr(replace("d${local.adf_name_random_suffix}${local.adf_name_location}", "-", ""), 0, 24))
  adf_ir_self_hosted_name = "ir-self-hosted-${local.adf_name_hostname}"
  adf_ls_blob_name        = "ls-adf-working-blob"
  adf_ls_file_name        = "ls-global-file"
  adf_ls_sql_name         = "ls-free-sql-database"
  adf_sql_connection      = "Server=tcp:${azurerm_mssql_server.this.fully_qualified_domain_name},${local.sql_port};Database=${azapi_resource.free_sql_database.name};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
}

resource "azurerm_storage_container" "adf_working" {
  name                  = "adf-working"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
resource "azurerm_role_assignment" "adf_working_blob_data_contributor" {
  scope                = azurerm_storage_container.adf_working.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.environment.principal_id
  description          = local.iac_message
}

module "data_factory" {
  source           = "Azure/avm-res-datafactory-factory/azurerm"
  version          = "~>0.2, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                = local.adf_name_hostname
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location

  managed_virtual_network_enabled = true
  public_network_enabled          = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true

  global_parameters = [
    {
      name  = "environmentPrefix"
      type  = "String"
      value = var.prefix
    },
    {
      name  = "location"
      type  = "String"
      value = module.environment_resource_group.resource.location
    },
    {
      name  = "resourceGroupName"
      type  = "String"
      value = module.environment_resource_group.resource.name
    },
    {
      name  = "private"
      type  = "Boolean"
      value = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? true : false
    }
  ]

  integration_runtime_self_hosted = {
    self_hosted = {
      name                                         = local.adf_ir_self_hosted_name
      self_contained_interactive_authoring_enabled = true
    }
  }

  linked_service_azure_blob_storage = {
    adf_working = {
      name                 = local.adf_ls_blob_name
      description          = "Linked service for the ${azurerm_storage_container.adf_working.name} container."
      service_endpoint     = azurerm_storage_account.this.primary_blob_endpoint
      storage_kind         = "StorageV2"
      use_managed_identity = true
      parameters = {
        containerName = azurerm_storage_container.adf_working.name
      }
    }
  }

  linked_service_azure_file_storage = {
    global = {
      name              = local.adf_ls_file_name
      description       = "Linked service for the ${azurerm_storage_share.global.name} file share."
      connection_string = azurerm_storage_account.this.primary_connection_string
      file_share        = azurerm_storage_share.global.name
      parameters = {
        fileShareName = azurerm_storage_share.global.name
      }
    }
  }

  ## Note: managed identity SQL access may still need a database user/grant at runtime;
  ## Terraform validation can’t prove that data-plane permission exists.
  linked_service_azure_sql_database = {
    free = {
      name                 = local.adf_ls_sql_name
      description          = "Linked service for the ${azapi_resource.free_sql_database.name} SQL database."
      connection_string    = local.adf_sql_connection
      use_managed_identity = true
      parameters = {
        databaseName = azapi_resource.free_sql_database.name
        serverName   = azurerm_mssql_server.this.name
      }
    }
  }

  managed_identities = {
    system_assigned = false
    user_assigned_resource_ids = [
      azurerm_user_assigned_identity.environment.id
    ]
  }

  role_assignments = {
    role_assignment_1 = {
      name                             = uuidv5("assignment1", "${module.environment_resource_group.resource.id}/Data Factory Contributor/${azurerm_user_assigned_identity.environment.principal_id}")
      role_definition_id_or_name       = "Data Factory Contributor"
      principal_id                     = azurerm_user_assigned_identity.environment.principal_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    role_assignment_2 = {
      name                             = uuidv5("assignment2", "${module.environment_resource_group.resource.id}/Data Factory Contributor/${azurerm_user_assigned_identity.environment.principal_id}")
      role_definition_id_or_name       = "Data Factory Contributor"
      principal_id                     = var.owner_entra_object_id
      skip_service_principal_aad_check = false
      principal_type                   = "User"
      description                      = local.iac_message
    }
  }
  lock = (tobool(var.data_pii) || tobool(var.data_phi)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

