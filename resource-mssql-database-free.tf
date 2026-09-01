locals {
  sql_free_database_friendly_name = "Free SQL Database"
  sql_free_database_name          = "sqldb-${var.prefix}-free"
  sql_free_database_location      = lower("${local.sql_free_database_name}-${lower(var.location)}")
  sql_free_database_random_suffix = substr(md5(local.sql_free_database_location), 0, 6)
  sql_free_database_name_hostname = lower(substr(replace("d${local.sql_free_database_random_suffix}${local.sql_free_database_location}", "-", ""), 0, 24))
}

resource "azurerm_user_assigned_identity" "free_sql_database" {
  name = "id-${local.sql_free_database_location}-readwrite"

  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location
  isolation_scope     = var.deploy_sql_failover ? null : "Regional"

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}
resource "time_sleep" "free_sql_database_identity_create_wait" {
  create_duration = "1m"
  depends_on      = [azurerm_user_assigned_identity.free_sql_database]
}

/*
data "azapi_resource_id" "publicMaintenanceConfiguration" {
  type      = "Microsoft.Maintenance/publicMaintenanceConfigurations@2023-04-01"
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  name      = "SQL-Default" ##local.regions[var.location].sql_maintenance_configuration_name
}
*/

resource "azapi_resource" "free_sql_database" {
  type      = "Microsoft.Sql/servers/databases@2025-02-01-preview"
  name      = local.sql_free_database_name
  parent_id = azurerm_mssql_server.this.id
  location  = azurerm_mssql_server.this.location

  identity {
    type = "UserAssigned"
    identity_ids = [
      ## Only one user assigned managed identity is supported at the Database Level.
      azurerm_user_assigned_identity.free_sql_database.id,
    ]
  }
  schema_validation_enabled = false
  body = {
    properties = {
      minCapacity  = 0.5
      maxSizeBytes = 34359738368
      ## autoPauseDelay                   = 15 ## -1 auto pause is disabled (not applicable to free tier)
      zoneRedundant                    = false
      isLedgerOn                       = false
      isIPv6Enabled                    = "Disabled" ## "Enabled"
      useFreeLimit                     = true
      preferredEnclaveType             = "VBS"
      freeLimitExhaustionBehavior      = "AutoPause" ## Other option: BillOverUsage
      availabilityZone                 = "NoPreference"
      requestedBackupStorageRedundancy = "Local"
      #maintenanceConfigurationId       = data.azapi_resource_id.publicMaintenanceConfiguration.id
    }

    sku = {
      name     = "GP_S_Gen5"
      tier     = "GeneralPurpose"
      family   = "Gen5"
      capacity = 4 // 4 is the maximum for the free tier
    }
  }
  response_export_values = ["*"]
  tags                   = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  depends_on = [
    module.environment_resource_group
  ]
}

resource "azurerm_mssql_database_extended_auditing_policy" "free_sql_database" {
  database_id            = azapi_resource.free_sql_database.id
  enabled                = true
  log_monitoring_enabled = true
}

output "sql_free_database_name" {
  description = "Name of the free SQL database."
  sensitive   = false
  value       = azapi_resource.free_sql_database.name
}

## Server=tcp:sqldb-aif-australiaeast-p1.database.windows.net,1433;Initial Catalog=sqldb-free-aif;Persist Security Info=False;User ID={your_username};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Authentication="Active Directory Integrated";

locals {
  ## Server Alias (ODBC) for the SQL database connection. This is used in the registry to define a connection alias for the SQL Server.
  ## eg: DBMSSOCN,myserver.domain.com,1433 or DBNMPNTW,\\myserver\pipe\sql\query
  ## (for registry, HKCU:\SOFTWARE\Microsoft\MSSQLServer\Client\ConnectTo)
  sql_database_connection_free_odbc_alias = "${azurerm_mssql_server.this.name},${azurerm_mssql_server.this.fully_qualified_domain_name},${local.sql_port}"

  sql_database_connection_free_encrypted   = "Server=tcp:${azurerm_mssql_server.this.fully_qualified_domain_name},${local.sql_port};Initial Catalog=${azapi_resource.free_sql_database.name};Authentication=Active Directory Integrated;TrustServerCertificate=False;Timeout=30;MultipleActiveResultSets=True;Encrypt=True\""
  sql_database_connection_free_unencrypted = "Server=tcp:${azurerm_mssql_server.this.fully_qualified_domain_name},${local.sql_port};Initial Catalog=${azapi_resource.free_sql_database.name};Authentication=Active Directory Integrated;TrustServerCertificate=False;Timeout=30;MultipleActiveResultSets=True;Encrypt=False\""
}

output "sql_database_connection_free_odbc_alias" {
  description = "Registry alias for the SQL database connection."
  sensitive   = false
  value       = local.sql_database_connection_free_odbc_alias
}
output "sql_database_connection_free_encrypted" {
  description = "Connection string for the SQL database using Entra ID authentication with encryption enabled. Ensure that your client supports Azure AD authentication and has the necessary permissions to connect."
  sensitive   = false
  value       = local.sql_database_connection_free_encrypted
}
output "sql_database_connection_free_unencrypted" {
  sensitive   = false
  description = "Connection string for the SQL database using Entra ID authentication with encryption disabled. Ensure that your client supports Azure AD authentication and has the necessary permissions to connect."
  value       = local.sql_database_connection_free_unencrypted
}

/*
resource "azurerm_key_vault_secret" "sql_database_connection_alias" {
  key_vault_id = azurerm_key_vault.sql_kv.id
  name         = "SQL-FREE-REGISTRY-ODBC-ALIAS"
  value        = local.sql_database_connection_free_odbc_alias
  depends_on = [
    azurerm_role_assignment.sql_kv_admin,
  ]
}
*/

resource "azurerm_key_vault_secret" "sql_database_connection_free_encrypted" {
  key_vault_id = azurerm_key_vault.sql_kv.id
  name         = "SQL-FREE-PRIMARY-CONNECTION-STRING-ENCRYPTED"
  value        = local.sql_database_connection_free_encrypted
  depends_on = [
    azurerm_role_assignment.sql_kv_admin,
  ]
}

resource "azurerm_key_vault_secret" "sql_database_connection_free_unencrypted" {
  key_vault_id = azurerm_key_vault.sql_kv.id
  name         = "SQL-FREE-PRIMARY-CONNECTION-STRING-UNENCRYPTED"
  value        = local.sql_database_connection_free_unencrypted
  depends_on = [
    azurerm_role_assignment.sql_kv_admin,
  ]
}

/*
resource "azurerm_automation_variable_string" "sql_database_connection_free_encrypted" {
  name                    = "SQL-DATABASE-CONNECTION-STRING-FREE-ENCRYPTED"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (var.data_pii == "yes" || var.data_phi == "yes") ? true : false

  value       = local.sql_database_connection_free_encrypted
  description = <<-DESC
  Connection String (Entra ID Integrated) to the Free SQL Server database (encrypted)
DESC
}

resource "azurerm_automation_variable_string" "sql_database_connection_free_unencrypted" {
  name                    = "SQL-DATABASE-CONNECTION-STRING-FREE-UNENCRYPTED"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (var.data_pii == "yes" || var.data_phi == "yes") ? true : false

  value       = local.sql_database_connection_free_unencrypted
  description = <<-DESC
  Connection String (Entra ID Integrated) to the Free SQL Server database (unencrypted)
DESC
}
*/

/*
resource "terraform_data" "grant_sql_database_access" {
  triggers_replace = {
    server_fqdn    = azurerm_mssql_server.this.fully_qualified_domain_name
    database_name  = azapi_resource.free_sql_database.name
    principal_name = azurerm_user_assigned_identity.free_sql_database.name
  }

  depends_on = [
    azurerm_mssql_server.this,
    azurerm_user_assigned_identity.free_sql_database,
    azapi_resource.free_sql_database,
  ]

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]

    command = <<-EOT
$sql = @"
IF NOT EXISTS (
  SELECT 1
  FROM sys.database_principals
  WHERE name = N'${azurerm_user_assigned_identity.free_sql_database.name}'
)
BEGIN
  CREATE USER [${azurerm_user_assigned_identity.free_sql_database.name}] FROM EXTERNAL PROVIDER;
END;

IF IS_ROLEMEMBER('db_datareader', N'${azurerm_user_assigned_identity.free_sql_database.name}') <> 1
BEGIN
  ALTER ROLE db_datareader ADD MEMBER [${azurerm_user_assigned_identity.free_sql_database.name}];
END;

IF IS_ROLEMEMBER('db_datawriter', N'${azurerm_user_assigned_identity.free_sql_database.name}') <> 1
BEGIN
  ALTER ROLE db_datawriter ADD MEMBER [${azurerm_user_assigned_identity.free_sql_database.name}];
END;
"@

## The SQL Server has to be publically accessible for this to work, or have a
## private endpoint configured and the local-exec provisioner must run from a machine that can access the private endpoint.
Invoke-Sqlcmd `
  -ServerInstance "${azurerm_mssql_server.this.fully_qualified_domain_name}" `
  -Database "${azapi_resource.free_sql_database.name}" `
  -AccessToken (Get-AzAccessToken -ResourceUrl "https://database.windows.net").Token `
  -ErrorAction Stop `
  -Query $sql
EOT
  }
}
*/
