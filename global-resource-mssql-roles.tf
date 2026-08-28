resource "azurerm_role_definition" "mssql-db-reader" {
  name        = "Database-MSSQL-Server-Reader"
  description = "Just enough SQL Database access to read a MS SQL Server and its Databases configuration (but not its data)"
  scope       = data.azurerm_subscription.current.id

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
  scope       = data.azurerm_subscription.current.id

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
  ## depends_on = [time_sleep.resource_group_create_wait]
}

/*
resource "azurerm_role_assignment" "mssql-db-restore" {
  scope                = azurerm_mssql_server.this.id
  role_definition_name = azurerm_role_definition.mssql-db-restore.name
  principal_id         = azurerm_user_assigned_identity.sqlserver.principal_id
  description          = local.iac_message
  depends_on           = [azurerm_role_definition.mssql-db-restore, azurerm_role_definition.mssql-db-reader]
}
*/
