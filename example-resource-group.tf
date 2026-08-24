
/*
resource "azurerm_monitor_diagnostic_setting" "exmrg1" {
  name                       = "Log-Metrics-${data.azurerm_subscription.current.display_name}-to-Azure-Monitor"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}
*/
/*
resource "azurerm_monitor_diagnostic_setting" "exmrg2" {
  name                       = "Audit-${data.azurerm_subscription.current.display_name}-to-Azure-Monitor"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "audit"
  }
}
*/
