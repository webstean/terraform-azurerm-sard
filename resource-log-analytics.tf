
## https://docs.kaidojarvemets.com/articles/azure-data-collection-rules-complete-guide

locals {
  law_friendly_name = "Log Analytics Workspace"
  law_name          = "law-${var.prefix}"
  law_name_location = lower("${local.law_name}-${lower(var.location)}")
  law_random_suffix = substr(md5(local.law_name_location), 0, 6)
  law_name_hostname = lower(substr(replace("l${local.law_random_suffix}${local.law_name_location}", "-", ""), 0, 24))
}

module "log_analytics_workspace" {
  source           = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry ## see variables.tf

  name                                      = local.law_name_location
  resource_group_name                       = module.environment_resource_group.resource.name
  location                                  = module.environment_resource_group.resource.location
  log_analytics_workspace_sku               = "PerGB2018"
  log_analytics_workspace_daily_quota_gb    = 5
  log_analytics_workspace_retention_in_days = 30 ## free

  log_analytics_workspace_identity = {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }

  role_assignments = {
    role_assignment_1 = {
      role_definition_id_or_name = "Monitoring Metrics Publisher"
      principal_id               = azurerm_user_assigned_identity.environment.principal_id
      description                = local.iac_message
    }
    role_assignment_2 = {
      role_definition_id_or_name = "Log Analytics Reader"
      principal_id               = azurerm_user_assigned_identity.environment.principal_id
      description                = local.iac_message
    }
    role_assignment_3 = {
      role_definition_id_or_name = "Log Analytics Contributor"
      principal_id               = azurerm_user_assigned_identity.environment.principal_id
      description                = local.iac_message
    }
  }

  #log_analytics_workspace_tables_update = {
  #  for name in local.law_basic_table_names : name => {
  #    name = name
  #    plan = "Basic"
  #  }
  #}

  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  depends_on = [
    module.environment_resource_group
  ]
}

module "application_insights" {
  source           = "Azure/avm-res-insights-component/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                          = "insights-${local.law_name}"
  resource_group_name           = module.environment_resource_group.resource.name
  location                      = module.environment_resource_group.resource.location
  workspace_id                  = module.log_analytics_workspace.resource_id
  retention_in_days             = 30
  daily_data_cap_in_gb          = (try(var.data_pii, false) || try(var.data_phi, false)) ? 10 : 1
  local_authentication_disabled = false

  role_assignments = {
    role_assignment_1 = {
      role_definition_id_or_name = "Monitoring Reader"
      principal_id               = azurerm_user_assigned_identity.environment.principal_id
      description                = local.iac_message
    }
    role_assignment_2 = {
      role_definition_id_or_name = "Reader"
      principal_id               = azurerm_user_assigned_identity.environment.principal_id
      description                = local.iac_message
    }
  }

  /*
  diagnostic_settings = {
    default = {
      workspace_resource_id = module.log_analytics_workspace.resource_id
      name                  = "diag-defaults"
      metrics = [
        {
          category = "AllMetrics"
          enabled  = true
        }
      ]
      logs = [
        {
          category = "AppAvailabilityResults"
          enabled  = true
        },
        {
          category = "AppEvents"
          enabled  = true
        },
        {
          category = "AppExceptions"
          enabled  = true
        },
        {
          category = "AppMetrics"
          enabled  = true
        },
        {
          category = "AppPerformanceCounters"
          enabled  = true
        },
        {
          category = "AppRequests"
          enabled  = true
        },
        {
          category = "AppSystemEvents"
          enabled  = true
        },
        {
          category = "AppTraces"
          enabled  = true
        },
        {
          category = "AppBrowserTimings"
          enabled  = true
        },
        {
          category = "AppDependencies"
          enabled  = true
        },
        {
          category = "AppPageViews"
          enabled  = true
        },
        {
          category = "OTelResources"
          enabled  = true
        }
      ]
    }
  }
*/
  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

locals {
  app_insights_smart_detection_rules = {
    slow_server_response_time         = "Slow server response time"
    slow_page_load_time               = "Slow page load time"
    potential_memory_leak_detected_1  = "Potential memory leak detected"
    potential_memory_leak_detected_2  = "Potential memory leak detected"
    long_dependency_duration          = "Long dependency duration"
    degradation_in_server_response    = "Degradation in server response time"
    degradation_in_dependency         = "Degradation in dependency duration"
    degradation_in_trace_severity     = "Degradation in trace severity ratio"
    abnormal_rise_in_exception_volume = "Abnormal rise in exception volume"
    abnormal_rise_in_daily_data       = "Abnormal rise in daily data volume"
  }
}
resource "azurerm_application_insights_smart_detection_rule" "rules" {
  for_each = local.app_insights_smart_detection_rules

  name                               = each.value
  application_insights_id            = module.application_insights.resource_id
  enabled                            = true
  send_emails_to_subscription_owners = true
  //additional_email_recipients        = [azurerm_application_insights.this.tags.owner_email]
}

resource "azurerm_log_analytics_linked_service" "this" {
  resource_group_name = module.environment_resource_group.resource.name
  workspace_id        = module.log_analytics_workspace.resource_id
  read_access_id      = azurerm_automation_account.this.id
}

/*
resource "azurerm_log_analytics_datasource_windows_performance_counter" "example" {
  name                = "example-lad-wpc"
  resource_group_name = module.environment_resource_group.resource.name
  workspace_name      = module.log_analytics_workspace.name
  object_name         = "CPU"
  instance_name       = "*"
  counter_name        = "CPU"
  interval_seconds    = 10
}
resource "azurerm_log_analytics_datasource_windows_event" "example" {
  name                = "example-lad-wpc"
  workspace_id = module.log_analytics_workspace.resource.resource_id
  workspace_name      = module.log_analytics_workspace.name
  event_log_name      = "Application"
  event_types         = ["Error"]
}
*/

/*
resource "azurerm_log_analytics_workspace_table_custom_log" "this1" {
  name         = "example_CL"
  workspace_id = module.log_analytics_workspace.resource.resource_id
  display_name = "Example_Custom_Log"
  description  = "This is an example custom log"
  plan         = "Basic"

  column {
    name         = "TimeGenerated"
    description  = "The description of the column."
    display_name = "Time Generated"
    type         = "dateTime"
  }
}
*/

resource "azurerm_application_insights_workbook" "workbook1" {
  name                = uuid() ## must be a GUID
  description         = "Example Workbook created via Terraform"
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location
  display_name        = "Workbook1"
  data_json = jsonencode({
    "version" = "Notebook/1.0",
    "items" = [
      {
        "type" = 1,
        "content" = {
          "json" = "Test2022"
        },
        "name" = "text - 0"
      }
    ],
    "isLocked" = false,
    "fallbackResourceIds" = [
      "Azure Monitor"
    ]
  })
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

# Sets every table currently in the Log Analytics workspace to the Basic
# plan, via the AVM module's `log_analytics_workspace_tables_update` input.
#
# IMPORTANT CAVEATS — read before using:
#
# 1. Not all tables support Basic. Azure Monitor maintains an allowlist (mostly
#    ingestion-heavy Azure service tables + custom DCR tables); a large set of
#    default/system tables — Usage, AzureActivity, Heartbeat, Perf, the classic
#    VM insights tables (VMComputer/VMProcess/VMConnection/VMBoundPort), the
#    classic Container insights tables, Defender/Security Center tables, and
#    Sentinel's own alert/incident tables — are Analytics-only and Azure will
#    reject a Basic switch for them (HTTP 400 "plan is not supported"). The
#    exclude list below is a starting point covering the common ones, not
#    exhaustive. Because the resource below uses for_each, one table failing
#    doesn't block the others — if apply errors on a table plan not in this
#    list, add its name to `law_basic_excluded_tables` and re-apply.
#
# 2. This is a snapshot, not a standing policy. The table list is read at
#    apply time via the Tables list API. Any table that gets created *after*
#    this apply (e.g. a new diagnostic setting sending to a table type that
#    didn't exist in this workspace before) will default to Analytics until
#    you run `terraform apply` again and it picks the new table up. If you
#    need this enforced continuously, re-run apply on a schedule (CI job,
#    Terraform Cloud scheduled run, etc.).
#
# 3. On the very first apply that creates the workspace, this data source has
#    nothing to list yet (table list is empty), so no tables get switched.
#    Run apply again once the workspace has tables (its own default set, plus
#    whatever's ingesting into it) to actually apply Basic.

data "azapi_resource_list" "law_tables" {
  type      = "Microsoft.OperationalInsights/workspaces/tables@2023-09-01"
  parent_id = module.log_analytics_workspace.resource_id

  response_export_values = {
    names = "value[].name"
  }
}

locals {
  law_basic_excluded_tables = [
    "Usage",
    "AzureActivity",
    "Alert",
    "Heartbeat",
    "Perf",
    "Operation",
    "ComputerGroup",
    "Update",
    "UpdateSummary",
    "ConfigurationData",
    "ConfigurationChange",
    "VMComputer",
    "VMProcess",
    "VMConnection",
    "VMBoundPort",
    "ContainerInventory",
    "ContainerNodeInventory",
    "ContainerImageInventory",
    "ContainerServiceLog",
    "SecurityBaseline",
    "SecurityBaselineSummary",
    "SecurityDetection",
    "SecurityRecommendation",
    "ProtectionStatus",
    "SecurityAlert",
    "SecurityIncident",
  ]

  law_all_table_names = try(data.azapi_resource_list.law_tables.output.names, [])

  law_basic_table_names = [
    for name in local.law_all_table_names : name
    if !contains(local.law_basic_excluded_tables, name)
  ]
}

output "azure_monitor_workspace_name" {
  description = "The name of the Azure Monitor workspace."
  sensitive   = false
  value       = azurerm_monitor_workspace.this.name
}

output "azure_monitor_workspace_id" {
  description = "The ID of the Azure Monitor workspace."
  sensitive   = false
  value       = azurerm_monitor_workspace.this.id
}

output "azure_monitor_workspace_location" {
  description = "The location of the Azure Monitor workspace."
  sensitive   = false
  value       = azurerm_monitor_workspace.this.location
}

/*
resource "azurerm_role_assignment" "defender_log_analytics1" {
  scope                = module.log_analytics_workspace.resource_id
  role_definition_name = "Log Analytics Contributor"
  ## Windows Defender ATP
  principal_id = "fc780465-2017-40d4-a0c5-307022471b92"
  description = "Making sure Windows Defender ATP (fc780465-2017-40d4-a0c5-307022471b92) has Contributor access to LAW"
}
resource "azurerm_role_assignment" "defender_log_analytics2" {
  scope                = module.log_analytics_workspace.resource_id
  role_definition_name = "Log Analytics Contributor"
  ## Azure Security for IoT
  principal_id = "cfbd4387-1a16-4945-83c0-ec10e46cd4da"
  description = "Making sure Azure Security for IoT (cfbd4387-1a16-4945-83c0-ec10e46cd4da) has Log Analytics Contributor access to LAW"
}
*/

resource "azurerm_monitor_data_collection_endpoint" "otel" {
  name                = local.law_name_hostname
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location

  # true = publicly reachable Azure Monitor endpoint
  # false = private link / AMPLS style only
  public_network_access_enabled = true

  description = "Public Azure Monitor Data Collection Endpoint for OTLP/custom ingestion"

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

output "logs_otel_dce_id" {
  description = "The ID of the Azure Monitor Data Collection Endpoint."
  sensitive   = false
  value       = azurerm_monitor_data_collection_endpoint.otel.id
}

output "logs_otel_logs_ingestion_endpoint" {
  description = "The OTEL logs ingestion endpoint of the Azure Monitor Data Collection Endpoint."
  sensitive   = false
  value       = azurerm_monitor_data_collection_endpoint.otel.logs_ingestion_endpoint
}

output "logs_otel_metrics_ingestion_endpoint" {
  description = "The OTEL metrics ingestion endpoint of the Azure Monitor Data Collection Endpoint."
  sensitive   = false
  value       = azurerm_monitor_data_collection_endpoint.otel.metrics_ingestion_endpoint
}

output "logs_otel_configuration_access_endpoint" {
  description = "The configuration access endpoint of the Azure Monitor Data Collection Endpoint."
  sensitive   = false
  value       = azurerm_monitor_data_collection_endpoint.otel.configuration_access_endpoint
}

