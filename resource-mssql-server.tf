locals {
  sql_server_friendly_name = "SQL Server"
  sql_server_name          = "sqldb-${var.prefix}"
  sql_server_location      = "${local.sql_server_name}-${lower(var.location)}"
  sql_server_random_suffix = substr(md5(local.sql_server_location), 0, 6)
  sql_server_hostname      = lower(substr(replace("s${local.sql_server_random_suffix}${local.sql_server_location}", "-", ""), 0, 24))
  sql_port                 = "1433"
}

resource "azurerm_subnet" "sqlserver" {
  name                            = "databases"
  resource_group_name             = module.environment_resource_group.resource.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [format("10.%s.101.0/24", local.regions[var.location].location_number)]
  default_outbound_access_enabled = false

  service_endpoints                             = local.service_endpoints
  private_link_service_network_policies_enabled = false
  ## Supported values: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled.
  ## Keep this as Enabled so private endpoint network policies remain active on this subnet unless a workload explicitly requires policy exemptions.
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_user_assigned_identity" "sqlserver" {
  name = "id-${local.sql_server_location}-sqlserver-readwrite"

  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location
  isolation_scope     = var.deploy_sql_failover ? null : "Regional"

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  lifecycle {
    create_before_destroy = true
  }
}
resource "time_sleep" "sqlserver_identity_create_wait" {
  create_duration = "1m"
  depends_on      = [azurerm_user_assigned_identity.sqlserver]
}

resource "azurerm_network_security_group" "inbound_sqlserver" {
  count = tobool(var.deploy_private_endpoints) ? 1 : 0

  name                = "nsg-sqlserver-${lower(module.environment_resource_group.resource.location)}-inbound"
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location

  security_rule {
    name                       = "Inbound-SQL-Server-Database-From-Internet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(local.sql_port)
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
    description                = "Inbound Allow SQL Server & Database from Internet"
  }

  security_rule {
    name                       = "Inbound-SQL-Server-Database-From-GatewayManager"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(local.sql_port)
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
    description                = "Inbound Allow SQL Server & Database from GatewayManager"
  }

  security_rule {
    name                       = "Inbound-SQL-Server-Database-From-VirtualNetwork"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(local.sql_port)
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
    description                = "Inbound Allow SQL Server & Database from VirtualNetwork"
  }

  security_rule {
    name                       = "Inbound-SQL-Server-Database-From-LoadBalancer"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(local.sql_port)
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
    description                = "Inbound Allow SQL Server & Database from LoadBalancer"
  }

  ## Inbound: Deny All
  security_rule {
    name                       = "Deny-Anything-Else-Inbound"
    priority                   = 4095
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Deny ALL Inbound as part of Zero Trust Networking"
  }

  ## Outbound: Deny All
  security_rule {
    name                       = "Deny-Anything-Else-Outbound"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    description                = "Deny ALL Outbound as part of Zero Trust Networking"
  }
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

resource "azurerm_role_assignment" "sqlstorage1" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.sqlserver.principal_id
  description          = local.iac_message
}
resource "azurerm_role_assignment" "sqlstorage2" {
  scope                = azurerm_storage_account.diag.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.sqlserver.principal_id
  description          = local.iac_message
}

resource "azurerm_role_assignment" "sql_svr_contributor" {
  scope                = module.environment_resource_group.resource_id
  role_definition_name = "SQL Server Contributor"
  principal_id         = azurerm_user_assigned_identity.environment.principal_id
  description          = local.iac_message
}
resource "azurerm_role_assignment" "sql_db_contributor" {
  scope                = module.environment_resource_group.resource_id
  role_definition_name = "SQL DB Contributor"
  principal_id         = azurerm_user_assigned_identity.environment.principal_id
  description          = local.iac_message
}

resource "azurerm_key_vault" "sql_kv" {
  name                       = local.sql_server_hostname
  resource_group_name        = module.environment_resource_group.resource.name
  location                   = module.environment_resource_group.resource.location
  sku_name                   = "standard"
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  purge_protection_enabled   = true
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  tags                       = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

# Grant the deploying principal permissions to create the key
resource "azurerm_role_assignment" "sql_kv_admin" {
  principal_id         = data.azurerm_client_config.current.object_id
  scope                = azurerm_key_vault.sql_kv.id
  role_definition_name = "Key Vault Administrator"
  description          = local.iac_message
}
resource "azurerm_role_assignment" "sql_kv_crypto" {
  principal_id         = azurerm_user_assigned_identity.sqlserver.principal_id
  scope                = azurerm_key_vault.sql_kv.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  description          = local.iac_message
}
resource "azurerm_key_vault_key" "tde" {
  key_opts = [
    "unwrapKey",
    "wrapKey",
  ]
  key_type     = "RSA"
  key_vault_id = azurerm_key_vault.sql_kv.id
  name         = "tde-key"
  key_size     = 2048

  rotation_policy {
    expire_after         = "P90D"
    notify_before_expiry = "P29D"

    automatic {
      time_before_expiry = "P30D"
    }
  }
  tags       = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  depends_on = [azurerm_role_assignment.sql_kv_admin]
}

/*
module "sql_server_this" {
  source           = "Azure/avm-res-sql-server/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                = "${local.sql_server_location}-p1"
  location            = module.environment_resource_group.resource.location
  resource_group_name = module.environment_resource_group.resource.name
  server_version      = "12.0"
  azuread_administrator = {
    login_username              = var.owner_entra_display_name
    object_id                   = var.owner_entra_object_id
    azuread_authentication_only = true
  }

  transparent_data_encryption_key_vault_key_id = azurerm_key_vault_key.tde.id

    managed_identities = {
    system_assigned = false
    user_assigned_resource_ids = [
      azurerm_user_assigned_identity.environment.id
    ]
  }

  /*
  diagnostic_settings = {
    diag_setting_1 = {
      name                           = "Logs to Azure Monitor ${local.sql_server_location}-p1"
      log_groups                     = ["allLogs", "audit"]
      metric_categories              = ["SLI", "Requests"]
      log_analytics_destination_type = null
      workspace_resource_id          = module.log_analytics_workspace.resource_id
    }
  }
*/

#private_endpoints = {
#  primary = {
#    private_dns_zone_resource_ids = [azurerm_private_dns_zone.this.id]
#    subnet_resource_id            = azurerm_subnet.this.id
#    subresource_name              = "sqlServer"
#  }
#}
/*
  public_network_access_enabled = false
  tags = merge(
    module.environment_resource_group.resource.tags,
    lookup(module.environment_resource_group.resource.tags, "stateless", "") == "yes" ? { stateless = "no" } : {}
  )
  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}
*/

resource "azurerm_mssql_server" "this" {
  name                                 = "${local.sql_server_location}-p1"
  resource_group_name                  = module.environment_resource_group.resource.name
  location                             = module.environment_resource_group.resource.location
  version                              = "12.0"
  public_network_access_enabled        = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true
  outbound_network_restriction_enabled = false
  azuread_administrator {
    login_username              = var.sql_administrator_group_display_name
    object_id                   = var.sql_administrator_group_object_id
    azuread_authentication_only = true
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.sqlserver.id]
  }
  primary_user_assigned_identity_id = azurerm_user_assigned_identity.sqlserver.id

  ## Possible values are Default, Proxy, and Redirect.
  connection_policy = "Default"

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

## https://learn.microsoft.com/en-us/azure/azure-sql/database/dns-alias-overview?view=azuresql
## A DNS alias can be used in place of the server name.
## Client programs can use the alias in their connection strings.
## The DNS alias provides a translation layer that can redirect your client programs to different servers.
## This layer spares you the difficulties of having to find and edit all the clients and their connection strings.
## Note, supported when using free SQL Server
resource "azurerm_mssql_server_dns_alias" "this" {
  count = var.support_free_sql_database ? 0 : 1

  name            = "${local.sql_server_hostname}1" ## database.windows.net
  mssql_server_id = azurerm_mssql_server.this.id
}

resource "azurerm_mssql_server" "this-failover" {
  count = var.deploy_sql_failover ? 1 : 0

  name                                 = "${local.sql_server_location}-f1"
  resource_group_name                  = module.environment_resource_group.resource.name
  location                             = local.regions[module.environment_resource_group.resource.location].default_rep_location
  version                              = "12.0"
  public_network_access_enabled        = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true
  outbound_network_restriction_enabled = false
  azuread_administrator {
    login_username              = var.sql_administrator_group_display_name
    object_id                   = var.sql_administrator_group_object_id
    azuread_authentication_only = true
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.sqlserver.id]
  }
  primary_user_assigned_identity_id = azurerm_user_assigned_identity.sqlserver.id

  ## Possible values are Default, Proxy, and Redirect.
  connection_policy = "Default"

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}
/*
resource "azurerm_mssql_firewall_rule" "this_rule1" {
  count = azurerm_mssql_server.this.public_network_access_enabled ? 1 : 0

  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
resource "azurerm_mssql_firewall_rule" "this_rule2" {
  count = azurerm_mssql_server.this.public_network_access_enabled ? 1 : 0

  name             = "AllowAll"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}
*/

## https://learn.microsoft.com/en-us/azure/azure-sql/database/dns-alias-overview?view=azuresql
## A DNS alias can be used in place of the server name.
## Client programs can use the alias in their connection strings.
## The DNS alias provides a translation layer that can redirect your client programs to different servers.
## This layer spares you the difficulties of having to find and edit all the clients and their connection strings.
resource "azurerm_mssql_server_dns_alias" "this_failover" {
  count = var.deploy_sql_failover ? 1 : 0

  name            = "${local.sql_server_hostname}2" ## database.windows.net
  mssql_server_id = azurerm_mssql_server.this-failover[0].id
}

/*
resource "azurerm_mssql_virtual_network_rule" "outbound-subnet" {
  name      = "outbound-subnet-via-service-endpoint"
  server_id = azurerm_mssql_server.this.id
  subnet_id = azurerm_subnet.outbound.id
}
*/

resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  server_id              = azurerm_mssql_server.this.id
  enabled                = true
  retention_in_days      = 8
  log_monitoring_enabled = true
}

/*
resource "azurerm_mssql_server_microsoft_support_auditing_policy" "this" {
  server_id                       = azurerm_mssql_server.this.id
  blob_storage_endpoint           = azurerm_storage_account.diag.primary_blob_endpoint
  storage_account_access_key      = azurerm_storage_account.diag.primary_access_key
  log_monitoring_enabled          = true
  storage_account_subscription_id = data.azurerm_client_config.current.subscription_id
  depends_on                      = [azurerm_role_assignment.sqlstorage1, azurerm_role_assignment.sqlstorage2]
}
*/

resource "azurerm_storage_container" "sqldiag" {
  name                  = lower(azurerm_mssql_server.this.name)
  storage_account_id    = azurerm_storage_account.diag.id
  container_access_type = "private"
}

resource "time_sleep" "resource_group_create_wait" {
  create_duration = "30s"
  depends_on      = [module.environment_resource_group]
}

/*
resource "azurerm_mssql_server_vulnerability_assessment" "this" {
  server_security_alert_policy_id = azurerm_mssql_server_security_alert_policy.this.id
  storage_container_path          = "${azurerm_storage_account.diag.primary_blob_endpoint}${azurerm_storage_container.sqldiag.name}"
  storage_account_access_key      = azurerm_storage_account.diag.primary_access_key

  recurring_scans {
    enabled                   = true
    email_subscription_admins = false
    #    emails = [
    #      azurerm_mssql_server.this.tags.owner_email,
    #    ]
  }
  depends_on = [azurerm_role_assignment.sqlstorage1, azurerm_role_assignment.sqlstorage2]
}
*/

/*
resource "azurerm_mssql_server_security_alert_policy" "this" {
  resource_group_name        = module.environment_resource_group.resource.name
  server_name                = azurerm_mssql_server.this.name
  state                      = "Enabled"
  storage_endpoint           = azurerm_storage_account.diag.primary_blob_endpoint
  storage_account_access_key = azurerm_storage_account.diag.primary_access_key
  retention_days             = 10
  email_account_admins       = true
  depends_on                 = [azurerm_role_assignment.sqlstorage1, azurerm_role_assignment.sqlstorage2]
}
*/

resource "azurerm_role_definition" "mssql-db-reader" {
  name        = "Database-MSSQL-Server-Reader"
  description = "Just enough SQL Database access to read a MS SQL Server and its Databases configuration (but not its data)"
  scope       = module.environment_resource_group.resource_id

  permissions {
    actions = [
      "Microsoft.Sql/servers/databases/currentSensitivityLabels/read",
      "Microsoft.Sql/servers/databases/providers/Microsoft.Insights/logDefinitions/read",
      "Microsoft.Sql/servers/databases/read",
      "Microsoft.Sql/servers/databases/recommendedSensitivityLabels/read",
      "Microsoft.Sql/servers/databases/sensitivityLabels/read",
      "Microsoft.Sql/servers/dnsAliases/acquire/action",
      "Microsoft.Sql/servers/dnsAliases/read",
      "Microsoft.Sql/servers/operations/read",
      "Microsoft.Sql/servers/read",
      "Microsoft.Sql/servers/recoverableDatabases/read",
      "Microsoft.Sql/servers/restorableDroppedDatabases/read",
    ]
    not_actions      = []
    data_actions     = []
    not_data_actions = []
  }
  depends_on = [time_sleep.resource_group_create_wait, azurerm_mssql_server.this, azurerm_mssql_server.this-failover]
}
resource "azurerm_role_definition" "mssql-db-restore" {
  name        = "Database-MSSQL-Server-Restore"
  description = "Just enough SQL Database access to overwrite (restore) a MS SQL Server and any of its Databases configuration (but not its data)"
  scope       = module.environment_resource_group.resource_id

  permissions {
    actions = [
      "Microsoft.Sql/servers/databases/currentSensitivityLabels/read",
      "Microsoft.Sql/servers/databases/providers/Microsoft.Insights/logDefinitions/read",
      "Microsoft.Sql/servers/databases/read",
      "Microsoft.Sql/servers/databases/write",  ## danger
      "Microsoft.Sql/servers/databases/delete", ## danger
      "Microsoft.Sql/servers/databases/recommendedSensitivityLabels/read",
      "Microsoft.Sql/servers/databases/sensitivityLabels/read",
      "Microsoft.Sql/servers/dnsAliases/acquire/action",
      "Microsoft.Sql/servers/dnsAliases/read",
      "Microsoft.Sql/servers/operations/read",
      "Microsoft.Sql/servers/read",
      "Microsoft.Sql/servers/recoverableDatabases/read",
      "Microsoft.Sql/servers/restorableDroppedDatabases/read",
    ]
    not_actions      = []
    data_actions     = []
    not_data_actions = []
  }
  depends_on = [time_sleep.resource_group_create_wait, azurerm_mssql_server.this, azurerm_mssql_server.this-failover]
}

resource "azurerm_role_assignment" "mssql-db-restore" {
  scope                = azurerm_mssql_server.this.id
  role_definition_name = azurerm_role_definition.mssql-db-restore.name
  principal_id         = azurerm_user_assigned_identity.sqlserver.principal_id
  description          = local.iac_message
  depends_on           = [azurerm_role_definition.mssql-db-restore, azurerm_role_definition.mssql-db-reader]
}

/*
resource "azurerm_monitor_diagnostic_setting" "mssql_server_metrics" {
  name                       = "Metrics-${azurerm_mssql_server.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_mssql_server.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
*/

resource "azapi_resource_action" "sql_server_automatic_tuning" {
  type        = "Microsoft.Sql/servers/automaticTuning@2021-11-01"
  resource_id = "${azurerm_mssql_server.this.id}/automaticTuning/current"
  method      = "PATCH"

  body = {
    properties = {
      desiredState = "Auto"

      options = {
        forceLastGoodPlan = {
          desiredState = "On"
        }

        createIndex = {
          desiredState = "On"
        }

        dropIndex = {
          desiredState = "On"
        }
      }
    }
  }
}

/*
## fixed price per month, around $120 per month or Hyperscale $1,200 per month, but you can scale up and down as needed
resource "azurerm_mssql_elasticpool" "basic" {
  name                = "${azurerm_mssql_server.this.name}-basic-epool"
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location
  server_name         = azurerm_mssql_server.this.name
  license_type        = "LicenseIncluded"
  max_size_gb         = 756
  enclave_type       = "VBS"

  sku {
    name     = "BasicPool"
    tier     = "Basic" ## Basic, Standard, Premium, GeneralPurpose, BusinessCritical, Hyperscale
    family   = "Gen5"
    capacity = 4
  }

  per_database_settings {
    min_capacity = 0.25
    max_capacity = 4
  }
  zone_redundant = false
  high_availability_replica_count = 0 ## 0 to 4
}
output "sql_server_elastic_pool_id" {
  value       = azurerm_mssql_elasticpool.basic.id
  sensitive   = false
  description = "The ID of the SQL Server elastic pool."
}
*/

output "sql_server_name" {
  value       = azurerm_mssql_server.this.name
  sensitive   = false
  description = "The name of the SQL Server."
}


output "sql_server_id" {
  value       = azurerm_mssql_server.this.id
  sensitive   = false
  description = "The ID of the SQL Server."
}

output "sql_server_hostname" {
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
  sensitive   = false
  description = "The fully qualified domain name (FQDN) of the SQL Server instance."
}

output "sql_server_dns_alias" {
  value       = try(azurerm_mssql_server_dns_alias.this[0].name, null)
  sensitive   = false
  description = "The fully qualified domain name (FQDN) alias of the SQL Server instance."
}

output "sql_server_failover_name" {
  value       = try(azurerm_mssql_server.this-failover[0].name, null)
  sensitive   = false
  description = "The name of the SQL Server failover instance (located in another region)."
}

output "sql_server_failover_hostname" {
  value       = try(azurerm_mssql_server.this-failover[0].fully_qualified_domain_name, null)
  sensitive   = false
  description = "The fully qualified domain name of the SQL Server failover instance."
}

output "sql_server_failover_dns_alias" {
  value       = try(azurerm_mssql_server_dns_alias.this_failover[0].name, null)
  sensitive   = false
  description = "The fully qualified domain name (FQDN) alias of the SQL Server failover instance."
}

output "sql_server_user_assigned_identity_id" {
  value       = azurerm_user_assigned_identity.sqlserver.id
  sensitive   = false
  description = "The Azure ID of the SQL Server instance primary user-assigned identity."
}

output "sql_server_user_assigned_identity_principal_id" {
  value       = azurerm_user_assigned_identity.sqlserver.principal_id
  sensitive   = false
  description = "The Entra ID principal ID (or Object_id) of the SQL Server instance primary user-assigned identity."
}
