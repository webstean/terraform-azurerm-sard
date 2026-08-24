locals {
  query_pack_queries = {
    failed_azure_operations = {
      display_name = "Azure Activity - Failed Operations"
      description  = "Failed control-plane operations across Azure resources."
      solutions    = null
      ## "AADDomainServices" "ADAssessment" "ADAssessmentPlus" "ADReplication" "ADSecurityAssessment" "AlertManagement"
      ## "AntiMalware" "ApplicationInsights" "AzureAssessment" "AzureSecurityOfThings" "AzureSentinelDSRE"
      ## "AzureSentinelPrivatePreview" "BehaviorAnalyticsInsights" "ChangeTracking" "CompatibilityAssessment"
      ## "ContainerInsights" "Containers" "CustomizedWindowsEventsFiltering" "DeviceHealthProd" "DnsAnalytics"
      ## "ExchangeAssessment" "ExchangeOnlineAssessment" "IISAssessmentPlus" "InfrastructureInsights" "InternalWindowsEvent"
      ## "LogManagement" "Microsoft365Analytics" "NetworkMonitoring" "SCCMAssessmentPlus" "SCOMAssessment" "SCOMAssessmentPlus"
      ## "Security" "SecurityCenter" "SecurityCenterFree" "SecurityInsights" "ServiceMap" "SfBAssessment" "SfBOnlineAssessment"
      ## "SharePointOnlineAssessment" "SPAssessment" "SQLAdvancedThreatProtection" "SQLAssessment" "SQLAssessmentPlus"
      ## "SQLDataClassification" "SQLThreatDetection" "SQLVulnerabilityAssessment" "SurfaceHub" "Updates" "VMInsights"
      ## "WEFInternalUat" "WEF_10x" "WEF_10xDSRE" "WaaSUpdateInsights" "WinLog" "WindowsClientAssessmentPlus"
      ## "WindowsEventForwarding" "WindowsFirewall" "WindowsServerAssessment" "WireData" "WireData2"],

      category       = "management"
      resource_types = "default"
      ## microsoft.aad/domainservices, microsoft.aadiam/tenants, microsoft.agfoodplatform/farmbeats, microsoft.analysisservices/servers,
      ## microsoft.apimanagement/service, microsoft.appconfiguration/configurationstores, microsoft.appplatform/spring,
      ## microsoft.attestation/attestationproviders, microsoft.authorization/tenants, microsoft.automation/automationaccounts,
      ## microsoft.autonomousdevelopmentplatform/accounts, microsoft.azurestackhci/virtualmachines, microsoft.batch/batchaccounts,
      ## microsoft.blockchain/blockchainmembers, microsoft.botservice/botservices, microsoft.cache/redis, microsoft.cdn/profiles,
      ## microsoft.cognitiveservices/accounts, microsoft.communication/communicationservices, microsoft.compute/virtualmachines,
      ## microsoft.compute/virtualmachinescalesets, microsoft.connectedcache/cachenodes,
      ## microsoft.connectedvehicle/platformaccounts, microsoft.conenctedvmwarevsphere/virtualmachines,
      ## microsoft.containerregistry/registries, microsoft.containerservice/managedclusters,
      ## microsoft.d365customerinsights/instances, microsoft.dashboard/grafana, microsoft.databricks/workspaces,
      ## microsoft.datacollaboration/workspaces, microsoft.datafactory/factories, microsoft.datalakeanalytics/accounts,
      ## microsoft.datalakestore/accounts, microsoft.datashare/accounts, microsoft.dbformariadb/servers,
      ## microsoft.dbformysql/servers, microsoft.dbforpostgresql/flexibleservers, microsoft.dbforpostgresql/servers,
      ## microsoft.dbforpostgresql/serversv2, microsoft.digitaltwins/digitaltwinsinstances,
      ## microsoft.documentdb/cassandraclusters, microsoft.documentdb/databaseaccounts, 
      ## microsoft.desktopvirtualization/applicationgroups, microsoft.desktopvirtualization/hostpools,
      ## microsoft.desktopvirtualization/workspaces, microsoft.devices/iothubs, microsoft.devices/provisioningservices,
      ## microsoft.dynamics/fraudprotection/purchase, microsoft.eventgrid/domains, microsoft.eventgrid/topics,
      ## microsoft.eventgrid/partnernamespaces, microsoft.eventgrid/partnertopics, microsoft.eventgrid/systemtopics,
      ## microsoft.eventhub/namespaces, microsoft.experimentation/experimentworkspaces, microsoft.hdinsight/clusters, 
      ## microsoft.healthcareapis/services, microsoft.informationprotection/datasecuritymanagement, microsoft.intune/operations,
      ## microsoft.insights/autoscalesettings, microsoft.insights/components, microsoft.insights/workloadmonitoring,
      ## microsoft.keyvault/vaults, microsoft.kubernetes/connectedclusters, microsoft.kusto/clusters,
      ## microsoft.loadtestservice/loadtests, microsoft.logic/workflows, microsoft.machinelearningservices/workspaces,
      ## microsoft.media/mediaservices, microsoft.netapp/netappaccounts/capacitypools, microsoft.network/applicationgateways,
      ## microsoft.network/azurefirewalls, microsoft.network/bastionhosts, microsoft.network/expressroutecircuits,
      ## microsoft.network/frontdoors, microsoft.network/loadbalancers, microsoft.network/networkinterfaces,
      ## microsoft.network/networksecuritygroups, microsoft.network/networksecurityperimeters,
      ## microsoft.network/networkwatchers/connectionmonitors, microsoft.network/networkwatchers/trafficanalytics,
      ## microsoft.network/publicipaddresses, microsoft.network/trafficmanagerprofiles, microsoft.network/virtualnetworks,
      ## microsoft.network/virtualnetworkgateways, microsoft.network/vpngateways, microsoft.networkfunction/azuretrafficcollectors,
      ## microsoft.openenergyplatform/energyservices, microsoft.openlogisticsplatform/workspaces, microsoft.operationalinsights/workspaces,
      ## microsoft.powerbi/tenants, microsoft.powerbi/tenants/workspaces, microsoft.powerbidedicated/capacities,
      ## microsoft.purview/accounts, microsoft.recoveryservices/vaults, microsoft.resources/azureactivity, 
      ## microsoft.scvmm/virtualmachines, microsoft.search/searchservices, microsoft.security/antimalwaresettings,
      ## microsoft.securityinsights/amazon, microsoft.securityinsights/anomalies, microsoft.securityinsights/cef,
      ## microsoft.securityinsights/datacollection, microsoft.securityinsights/dnsnormalized, microsoft.securityinsights/mda,
      ## microsoft.securityinsights/mde, microsoft.securityinsights/mdi, microsoft.securityinsights/mdo,
      ## microsoft.securityinsights/networksessionnormalized, microsoft.securityinsights/office365,
      ## microsoft.securityinsights/purview, microsoft.securityinsights/securityinsights, 
      ## microsoft.securityinsights/securityinsights/mcas, microsoft.securityinsights/tvm,
      ## microsoft.securityinsights/watchlists, microsoft.servicebus/namespaces, microsoft.servicefabric/clusters,
      ## microsoft.signalrservice/signalr, microsoft.signalrservice/webpubsub, microsoft.sql/managedinstances,
      ## microsoft.sql/servers, microsoft.sql/servers/databases, microsoft.storage/storageaccounts, microsoft.storagecache/caches,
      ## microsoft.streamanalytics/streamingjobs, microsoft.synapse/workspaces, microsoft.timeseriesinsights/environments,
      ## microsoft.videoindexer/accounts, microsoft.web/sites, microsoft.workloadmonitor/monitors, resourcegroup and subscription.
      body = <<-KQL
        AzureActivity
        | where ActivityStatusValue == "Failure"
        | project TimeGenerated, ResourceGroup, ResourceProviderValue, OperationNameValue, Caller, ActivitySubstatusValue, Properties
        | order by TimeGenerated desc
      KQL
    }

    deployment_failures = {
      display_name = "Azure Deployments - Failures"
      description  = "Failed ARM/Bicep/Terraform-style deployment operations."
      solutions    = null
      category     = "management"
      body         = <<-KQL
        AzureActivity
        | where OperationNameValue has "deployments"
        | where ActivityStatusValue == "Failure"
        | project TimeGenerated, ResourceGroup, Caller, OperationNameValue, ActivitySubstatusValue, Properties
        | order by TimeGenerated desc
      KQL
    }

    #    keyvault_denied = {
    #      display_name = "Key Vault - Denied Requests"
    #      description  = "Key Vault denied/forbidden access attempts."
    #      category     = "security"
    #      body         = <<-KQL
    #        AzureDiagnostics
    #        | where ResourceProvider == "MICROSOFT.KEYVAULT"
    #        | where ResultType in ("Forbidden", "Unauthorized") or httpStatusCode_d in (401, 403)
    #        | project TimeGenerated, Resource, OperationName, ResultType, CallerIPAddress, identity_claim_appid_g, identity_claim_oid_g
    #        | order by TimeGenerated desc
    #      KQL
    #    }

    storage_auth_failures = {
      display_name = "Storage - Auth Failures"
      description  = "Storage account authorization and authentication failures."
      solutions    = null
      category     = "resources"
      body         = <<-KQL
        StorageBlobLogs
        | where StatusCode in (401, 403)
        | project TimeGenerated, AccountName, OperationName, AuthenticationType, StatusCode, StatusText, CallerIpAddress, Uri
        | order by TimeGenerated desc
      KQL
    }

    sql_errors = {
      display_name = "Azure SQL - Errors"
      description  = "Recent SQL errors from diagnostic logs."
      solutions    = null
      category     = "resources"
      body         = <<-KQL
        AzureDiagnostics
        | where ResourceProvider == "MICROSOFT.SQL"
        | where Category has_any ("Errors", "SQLSecurityAuditEvents")
        | project TimeGenerated, Resource, Category, OperationName, action_name_s, statement_s, client_ip_s, succeeded_s
        | order by TimeGenerated desc
      KQL
    }

    application_gateway_5xx = {
      display_name = "Application Gateway - 5xx Errors"
      description  = "Application Gateway backend/server errors."
      category     = "resources"
      solutions    = null
      body         = <<-KQL
        AzureDiagnostics
        | where ResourceProvider == "MICROSOFT.NETWORK"
        | where Category == "ApplicationGatewayAccessLog"
        | where httpStatus_d >= 500
        | summarize Count = count() by bin(TimeGenerated, 5m), Resource, backendPoolName_s, httpStatus_d
        | order by TimeGenerated desc
      KQL
    }

    #    azure_firewall_denies = {
    #      display_name = "Azure Firewall - Denied Traffic"
    #      description  = "Denied traffic from Azure Firewall logs."
    #      category     = "resources"
    #  solutions    = null
    #      body         = <<-KQL
    #        AzureDiagnostics
    #        | where ResourceProvider == "MICROSOFT.NETWORK"
    #        | where Category has "AzureFirewall"
    #        | where msg_s has "Deny"
    #        | project TimeGenerated, Resource, Category, msg_s
    #        | order by TimeGenerated desc
    #      KQL
    #    }

    #    container_apps_errors = {
    #      display_name = "Container Apps - Console Errors"
    #      description  = "Recent error output from Azure Container Apps console logs."
    #      category     = "resources"
    #      solutions    = null
    #      body         = <<-KQL
    #        ContainerAppConsoleLogs_CL
    #        | where Log_s has_any ("error", "exception", "fail", "fatal")
    #        | project TimeGenerated, ContainerAppName_s, RevisionName_s, Log_s
    #        | order by TimeGenerated desc
    #      KQL
    #    }
  }
}

resource "azurerm_log_analytics_query_pack" "platform" {
  name                = "default-query-pack-${var.prefix}-${var.customer}"
  resource_group_name = module.environment_resource_group.resource.name
  location            = azurerm_resource_group.environment.location
  tags                = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

## OpenTelemetry metrics, plus Prometheus
resource "azurerm_monitor_workspace" "this" {
  name                = local.law_name_location
  resource_group_name = module.environment_resource_group.resource.name
  location            = azurerm_resource_group.environment.location

  public_network_access_enabled = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

/*
resource "azurerm_log_analytics_query_pack_query" "queries" {
  for_each = local.query_pack_queries

  query_pack_id = azurerm_log_analytics_query_pack.platform.id

  display_name = each.value.display_name
  description  = each.value.description
  body         = trimspace(each.value.body)
  solutions    = each.value.solutions

  # Query pack categories are limited to 5 labels by the API.
  categories = slice(
    compact(distinct(try(each.value.categories, [each.value.category]))),
    0,
    min(5, length(compact(distinct(try(each.value.categories, [each.value.category])))))
  )

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}
*/

