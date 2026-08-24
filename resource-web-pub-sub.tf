locals {
  pubsub_friendly_name = "Publish Web Pub Sub"
  pubsub_name          = substr("pubsub${var.prefix}", 0, 8) ## can only be 9 characters or less
  pubsub_name_location = lower("${local.pubsub_name}${lower(var.location)}")
  pubsub_random_suffix = substr(md5(local.pubsub_name_location), 0, 6)
  pubsub_name_hostname = lower(substr(replace("cc${local.pubsub_random_suffix}${local.pubsub_name_location}", "-", ""), 0, 24))
}

resource "azurerm_web_pubsub" "this" {
  name                = local.pubsub_name_hostname
  location            = azurerm_resource_group.environment.location
  resource_group_name = azurerm_resource_group.environment.name

  sku      = "Free_F1" # Free_F1, Standard_S1, Premium_P1
  capacity = 1

  local_auth_enabled            = false
  tls_client_cert_enabled       = false
  public_network_access_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }

  live_trace {
    enabled                   = true
    connectivity_logs_enabled = true
    messaging_logs_enabled    = true
    http_request_logs_enabled = true
  }

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

resource "azurerm_role_assignment" "web_pubsub_owner1" {
  scope                = azurerm_web_pubsub.this.id
  role_definition_name = "Web PubSub Service Owner"
  principal_id         = var.owner_entra_object_id
  description          = local.iac_message
}

#resource "azurerm_web_pubsub_hub" "this" {
#  name          = "${local.pubsub_name}-notification"
#  web_pubsub_id = azurerm_web_pubsub.this.id

##  event_handler {
##    url_template       = "https://${azurerm_linux_function_app.this.default_hostname}/runtime/webhooks/webpubsub"
##    user_event_pattern = "*"
##    system_events      = ["connect", "connected", "disconnected"]
##  }

##  anonymous_connections_enabled = false
##}

/*
# Diagnostic settings
resource "azurerm_monitor_diagnostic_setting" "webpubsub" {
  name                       = "webpubsub-diag"
  target_resource_id         = azurerm_web_pubsub.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category = "ConnectivityLogs"
  }
  enabled_log {
    category = "MessagingLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}
*/

/*
resource "azurerm_web_pubsub_custom_certificate" "this" {
  name                  = "example-cert"
  web_pubsub_id         = azurerm_web_pubsub.this.id
  custom_certificate_id = azurerm_key_vault_certificate.example.id

  depends_on = [azurerm_key_vault_access_policy.example]
}

resource "azurerm_web_pubsub_custom_dns_zone" "this" {
  name                             = "example-domain"
  domain_name                      = "tftest.com"
  web_pubsub_id                    = azurerm_web_pubsub.this.id
  web_pubsub_custom_certificate_id = azurerm_web_pubsub_custom_certificate.this.id
}
*/

output "web_pubsub_id" {
  description = "The ID of the Web Pub Sub."
  sensitive   = false
  value       = azurerm_web_pubsub.this.id
}

output "web_pubsub_hostname" {
  description = "The hostname of the Web Pub Sub."
  sensitive   = false
  value       = azurerm_web_pubsub.this.hostname
}
