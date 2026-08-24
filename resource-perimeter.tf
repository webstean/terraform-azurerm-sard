locals {
  perimeter_friendly_name = "Network Security Perimeter"
  perimeter_name          = "perimeter-${var.prefix}"
  perimeter_name_location = lower("${local.perimeter_name}-${lower(var.location)}")
  perimeter_random_suffix = substr(md5(local.perimeter_name_location), 0, 6)
  perimeter_name_hostname = lower(substr(replace("p${local.perimeter_random_suffix}${local.perimeter_name_location}", "/[^a-z0-9]/", ""), 0, 24))
}

## https://learn.microsoft.com/en-us/azure/private-link/network-security-perimeter-concepts
## Today, the supported resources are:
## Azure Monitor	
## Azure AI Search
## Cosmos DB
## Event Hubs
## Key Vault
## SQL DB Server
## Storage Accounts
## Azure OpenAI service	Microsoft.CognitiveServices(kind="OpenAI")		Public Preview	Not Available
## Microsoft Foundry	Microsoft.CognitiveServices/accounts
## Microsoft.CognitiveServices(kind="AIServices")		Generally Available	Generally Available
## Azure Service Bus	Microsoft.ServiceBus/namespaces
## Data Collection Endpoint Microsoft.Insights/dataCollectionEndpoints

resource "azurerm_network_security_perimeter" "this" {
  name                = local.perimeter_name
  resource_group_name = module.environment_resource_group.resource.name
  location            = azurerm_resource_group.environment.location
  tags                = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}
resource "azurerm_network_security_perimeter_profile" "this" {
  name                          = "profile-${local.perimeter_name}"
  network_security_perimeter_id = azurerm_network_security_perimeter.this.id
}

resource "azurerm_network_security_perimeter_access_rule" "inbound-rule1" {
  name                                  = "${local.perimeter_name}-inbound-rule1"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.this.id
  direction                             = "Inbound" ## "Inbound" or "Outbound"

  ## Can only be specified when direction is set to Inbound
  subscription_ids = [data.azurerm_subscription.current.id]
}
/*
resource "azurerm_network_security_perimeter_access_rule" "inbound-rule2" {
  name                                  = "${local.perimeter_name}-inbound-rule2"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.this.id
  direction                             = "Inbound" ## "Inbound" or "Outbound"

  service_tags = [
    #    "AzureCloud.${title(var.location)}",
    "AzureCloud",
  ]
}
*/
resource "azurerm_network_security_perimeter_access_rule" "inbound-rule3" {
  name                                  = "${local.perimeter_name}-inbound-allowed-rule3"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.this.id
  direction                             = "Inbound" ## "Inbound" or "Outbound"

  ## Can only be specified when direction is set to Inbound
  address_prefixes = var.security_perimeter_inbound_public_ips
}

resource "azurerm_network_security_perimeter_access_rule" "outbound-rule1" {
  name                                  = "${local.perimeter_name}-outbound-rule1"
  network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.this.id
  direction                             = "Outbound" ## "Inbound" or "Outbound"

  fqdns = var.security_perimeter_outbound_fqdns
}

# Note: Association commented out due to provider inconsistency - resource type may not support NSP association
# resource "azurerm_network_security_perimeter_association" "outbound-rule1" {
#   name                                  = "${local.perimeter_name}-outbound-rule1-association"
#   access_mode                           = "Enforced"
#   network_security_perimeter_profile_id = azurerm_network_security_perimeter_profile.this.id
#   resource_id                           = module.log_analytics_workspace.resource_id
# }

/*
resource "azurerm_monitor_diagnostic_setting" "nsp1" {
  name                       = "Logs-${azurerm_network_security_perimeter.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_network_security_perimeter.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
}

resource "azurerm_monitor_diagnostic_setting" "nsp2" {
  name                       = "Metrics-${azurerm_network_security_perimeter.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_network_security_perimeter.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
*/

data "azurerm_resources" "environment" {
  resource_group_name = module.environment_resource_group.resource.name
  #required_tags       = { "app" = "andrew" }
}


#output "environment_resources" {
#  description = "All the Azure resources that are in this environment"
#  sensitive   = false
#  value       = data.azurerm_resources.environment
#}

# Filter for Azure Network Security Perimeter supported resources
locals {
  supported_perimeter_resource_types = [
    "Microsoft.Insights/dataCollectionEndpoints", # Azure Monitor
    "Microsoft.OperationalInsights/workspaces",   # Azure Monitor
    "Microsoft.Insights/actionGroups",            # Azure Monitor
    "Microsoft.Insights/scheduledQueryRules",     # Azure Monitor
    "Microsoft.Search/searchServices",            # Azure AI Search
    "Microsoft.DocumentDB/databaseAccounts",      # Cosmos DB
    "Microsoft.EventHub/namespaces",              # Event Hubs
    "Microsoft.KeyVault/vaults",                  # Key Vault
    "Microsoft.Sql/servers",                      # SQL DB Server
    "Microsoft.CognitiveServices/accounts",       # Microsoft Foundry / OpenAI
    "Microsoft.ServiceBus/namespaces",            # Azure Service Bus
  ]
}

# Filter environment resources to include only those supported by Azure Network Security Perimeter
locals {
  perimeter_candidate_resources = {
    for r in data.azurerm_resources.environment.resources : r.id => r
    if contains(local.supported_perimeter_resource_types, r.type)
  }
}

output "security_perimeter_id" {
  description = "Azure Network Security Perimeter ID for this environment"
  sensitive   = false
  value       = azurerm_network_security_perimeter.this.id
}

output "network_security_perimeter_profile_id" {
  description = "Azure Network Security Perimeter Profile ID for this environment"
  sensitive   = false
  value       = azurerm_network_security_perimeter_profile.this.id
}

output "security_perimeter_resources" {
  description = "Resources that need to be added to the Azure Network Security Perimeter"
  sensitive   = false
  value       = local.perimeter_candidate_resources
}

