locals {
  api_display_name = var.owner_entra_display_name
  api_connections = {
    microsoft365_connection = {
      name             = "office365"
      managed_api_id   = "office365"
      connectionString = null
    }
    azure_arm_connection = {
      name             = "arm"
      managed_api_id   = "arm"
      connectionString = null
    }
    azure_servicebus = {
      name             = "servicebus"
      managed_api_id   = "servicebus"
      connectionString = null
    }
    sharepoint_online = {
      name             = "sharepointonline"
      managed_api_id   = "sharepointonline"
      connectionString = null
    }
    teams = {
      name             = "teams"
      managed_api_id   = "teams"
      connectionString = null
    }
    azuread = {
      name             = "azuread"
      managed_api_id   = "azuread"
      connectionString = null
    }
    github = {
      name             = "github"
      managed_api_id   = "github"
      connectionString = null
    }
    dynamicscrmonline = {
      name             = "dynamicscrmonline"
      managed_api_id   = "dynamicscrmonline"
      connectionString = null
    }
  }
}

resource "azurerm_api_connection" "connections" {
  for_each = local.api_connections

  display_name        = local.api_display_name
  managed_api_id      = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Web/locations/australiaeast/managedApis/${each.value.managed_api_id}"
  name                = lower(each.value.name)
  parameter_values    = each.value.connectionString
  resource_group_name = module.environment_resource_group.resource.name
  tags                = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  lifecycle {
    # NOTE: since the connectionString is a secure value it's not returned from the API
    ignore_changes = [parameter_values]
  }
}

# servicebus	Azure Service Bus
# azureblob	Azure Blob Storage
# azuretables	Azure Table Storage
# azurequeues	Azure Queue Storage
# sql	Azure SQL / SQL Server
# keyvault	Azure Key Vault
# office365	Office 365 Outlook
# sharepointonline	SharePoint Online
# teams	Microsoft Teams
# onedrive	OneDrive
# onedriveforbusiness	OneDrive for Business
# azureeventgrid	Event Grid
# eventhubs	Event Hubs
# azuremonitorlogs	Azure Monitor Logs
# azureautomation	Azure Automation
# azuread	Azure AD
# outlook	Outlook.com
# twitter	Twitter/X
# slack	Slack
# github	GitHub
# salesforce	Salesforce
# dynamicscrmonline	Dynamics 365
