locals {
  comms_name          = "cm-${var.prefix}"
  comms_name_location = lower("${local.comms_name}-${lower(var.location)}")
  comms_random_suffix = substr(md5(local.comms_name_location), 0, 6)
  comms_name_hostname = lower(substr(replace("cn${local.comms_random_suffix}${local.comms_name_location}", "-", ""), 0, 24))
}

module "comms_keyvault" {
  source           = "Azure/avm-res-keyvault-vault/azurerm"
  version          = "~>0.7, < 1.0"
  enable_telemetry = var.enable_telemetry

  name                            = local.comms_name_hostname
  resource_group_name             = module.environment_resource_group.resource.name
  location                        = module.environment_resource_group.resource.location
  tenant_id                       = data.azurerm_client_config.current.tenant_id
  sku_name                        = "standard"
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7
  public_network_access_enabled   = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true
  legacy_access_policies_enabled  = false
  enabled_for_deployment          = false ## Whether Azure Virtual Machines are permitted to retrieve certificates
  enabled_for_disk_encryption     = false ## Whether Azure Disk Encryption is permitted to retrieve secrets from the vault
  enabled_for_template_deployment = false ## Whether Azure Resource Manager is permitted to retrieve secrets from the vault
  network_acls = {
    default_action             = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? "Deny" : "Allow"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [for subnets in azurerm_virtual_network.this.subnet : subnets.id if contains(subnets.service_endpoints, "Microsoft.KeyVault")]
  }

  /*
  diagnostic_settings = {
    diag_setting_1 = {
      name                           = "Logs-Metrics-And-Audit to Azure Monitor ${module.log_analytics_workspace.resource.name}"
      log_groups                     = ["allLogs", "audit"]
      metric_categories              = ["AllMetrics"]
      log_analytics_destination_type = null
      workspace_resource_id          = module.log_analytics_workspace.resource_id
    }
  }
*/
  role_assignments = {
    role_assignment_1 = {
      name                             = uuidv5("url", "${module.environment_resource_group.resource.id}/Key Vault Secrets User/${azurerm_user_assigned_identity.environment.principal_id}")
      role_definition_id_or_name       = "Key Vault Secrets User"
      principal_id                     = azurerm_user_assigned_identity.environment.principal_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    role_assignment_2 = {
      name                             = uuidv5("url", "${module.environment_resource_group.resource.id}/Key Vault Administrator/${azurerm_user_assigned_identity.environment.principal_id}")
      role_definition_id_or_name       = "Key Vault Administrator"
      principal_id                     = azurerm_user_assigned_identity.environment.principal_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    role_assignment_3 = {
      name                             = uuidv5("url", "${module.environment_resource_group.resource.id}/Key Vault Administrator/${data.azurerm_client_config.current.object_id}")
      role_definition_id_or_name       = "Key Vault Administrator"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    role_assignment_4 = {
      name                             = uuidv5("url", "${module.environment_resource_group.resource.id}/Key Vault Secrets Officer/${data.azurerm_client_config.current.object_id}")
      role_definition_id_or_name       = "Key Vault Secrets Officer"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
  }

  lock = (tobool(var.data_pii) || tobool(var.data_phi)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  depends_on = [
    azurerm_user_assigned_identity.environment
  ]
}

locals {
  comms_keyvault_id = module.comms_keyvault.resource_id
}

// info: https://learn.microsoft.com/en-us/azure/communication-services/overview
// the comms service is a global service
resource "azurerm_communication_service" "this" {

  name                = local.comms_name_location
  resource_group_name = module.environment_resource_group.resource.name
  data_location       = local.regions[module.environment_resource_group.resource.location].data_location

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
  timeouts {
    create = "60m"
    delete = "60m"
  }
}

resource "azapi_update_resource" "comms-identity" {
  type        = "Microsoft.Communication/communicationServices@2026-03-18"
  resource_id = azurerm_communication_service.this.id
  body = {
    identity = {
      type = "SystemAssigned"
    }
  }
  depends_on = [
    azurerm_communication_service.this,
    azurerm_user_assigned_identity.environment
  ]
}

/*
resource "azurerm_monitor_diagnostic_setting" "commservervice" {
  name                       = "Metrics-and-Logs-${azurerm_communication_service.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_communication_service.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}
*/

resource "azurerm_role_assignment" "comms_service_owner1" {
  scope                = azurerm_communication_service.this.id
  role_definition_name = "Communication and Email Service Owner"
  principal_id         = var.owner_entra_object_id
  description          = local.iac_message
}
resource "azurerm_role_assignment" "comms_service_owner2" {
  scope                = azurerm_communication_service.this.id
  role_definition_name = "Communication and Email Service Owner"
  principal_id         = azurerm_user_assigned_identity.environment.principal_id
  description          = local.iac_message
}


resource "azurerm_email_communication_service" "this" {
  name                = "${local.comms_name_location}-email"
  resource_group_name = module.environment_resource_group.resource.name
  data_location       = local.regions[module.environment_resource_group.resource.location].data_location
  tags                = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

resource "azurerm_email_communication_service_domain" "this" {
  name                             = "AzureManagedDomain"
  email_service_id                 = azurerm_email_communication_service.this.id
  domain_management                = "AzureManaged"
  user_engagement_tracking_enabled = true
  tags                             = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

resource "azurerm_communication_service_email_domain_association" "comms" {
  communication_service_id = azurerm_communication_service.this.id
  email_service_domain_id  = azurerm_email_communication_service_domain.this.id
}

resource "azurerm_email_communication_service_domain_sender_username" "this" {
  ## default is "DoNotReply"
  name                    = "${upper(var.prefix)}-DoNotReply"
  email_service_domain_id = azurerm_email_communication_service_domain.this.id
  display_name            = "${upper(var.prefix)}-Do Not Reply"
}

resource "azurerm_key_vault_secret" "primary-connection" {
  key_vault_id = module.comms_keyvault.resource_id
  name         = "COMMS-PRIMARY-CONNECTION-STRING"
  value        = azurerm_communication_service.this.primary_connection_string
  depends_on = [
    module.comms_keyvault,
    azurerm_role_assignment.comms_service_owner1,
    azurerm_role_assignment.comms_service_owner2
  ]
}
resource "azurerm_key_vault_secret" "primary-key" {
  key_vault_id = module.comms_keyvault.resource_id
  name         = "COMMS-PRIMARY-API-KEY"
  value        = azurerm_communication_service.this.primary_key
  depends_on = [
    module.comms_keyvault,
    azurerm_role_assignment.comms_service_owner1,
    azurerm_role_assignment.comms_service_owner2
  ]
}
resource "azurerm_key_vault_secret" "secondary-connection" {
  key_vault_id = module.comms_keyvault.resource_id
  name         = "COMMS-SECONDARY-CONNECTION-STRING"
  value        = azurerm_communication_service.this.secondary_connection_string
  depends_on = [
    module.comms_keyvault,
    azurerm_role_assignment.comms_service_owner1,
    azurerm_role_assignment.comms_service_owner2
  ]
}
resource "azurerm_key_vault_secret" "secondary-key" {
  key_vault_id = module.comms_keyvault.resource_id
  name         = "COMMS-SECONDARY-API-KEY"
  value        = azurerm_communication_service.this.secondary_key
  depends_on = [
    module.comms_keyvault,
    azurerm_role_assignment.comms_service_owner1,
    azurerm_role_assignment.comms_service_owner2
  ]
}

/*
resource "azurerm_app_configuration_key" "comms_primary_string" {
  configuration_store_id = module.appconfiguration.resource_id
  key                    = "COMMS-PRIMARY-CONNECTION-STRING"
  label                  = "basic"
  value                  = azurerm_communication_service.this.primary_connection_string
  depends_on = [
    module.appconfiguration
  ]
}
resource "azurerm_app_configuration_key" "comms_secondary_string" {
  configuration_store_id = module.appconfiguration.resource_id
  key                    = "COMMS-SECONDARY-CONNECTION-STRING"
  label                  = "basic"
  value                  = azurerm_communication_service.this.secondary_connection_string
  depends_on = [
    module.appconfiguration
  ]
}

resource "azurerm_app_configuration_key" "comms_api_key_primary" {
  configuration_store_id = module.appconfiguration.resource_id
  key                    = "COMMS-PRIMARY-API-KEY"
  label                  = "basic"
  value                  = azurerm_communication_service.this.primary_key
  depends_on = [
    module.appconfiguration
  ]
}

resource "azurerm_app_configuration_key" "comms_api_key_secondary" {
  configuration_store_id = module.appconfiguration.resource_id
  key                    = "COMMS-SECONDARY-API-KEY"
  label                  = "basic"
  value                  = azurerm_communication_service.this.secondary_key
  depends_on = [
    module.appconfiguration
  ]
}
*/

/*
resource "azurerm_key_vault_key" "comms_app_configuration" {
  for_each = (var.data_pii == "yes" || var.data_phi == "yes") ? data.azurerm_key_vault.shared_vault : {}

  name         = "comms-appconfiguration-encryption-key-${each.key}"
  key_vault_id = each.value.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey"
  ]
}
*/
locals {
  notification_hub_sku = "Free"
}
resource "azurerm_notification_hub_namespace" "this" {
  name                = "${local.comms_name_location}-namespace"
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location
  namespace_type      = "NotificationHub"
  sku_name            = local.notification_hub_sku
}

resource "azurerm_notification_hub" "this" {
  name                = "${local.comms_name_location}-hub"
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location
  namespace_name      = azurerm_notification_hub_namespace.this.name
  /*
  ## VAPID
  browser_credential {
    subject           = "subject"
    vapid_private_key = "private"
    vapid_public_key  = "public"
  }
  ## Google
  gcm_credential {
    api_key = "api-key"
  }
  ## Apple
  apns_credential {
    application_mode = "SandBox"
    bundle_id        = "com.hashicorp.example"
    key_id           = "key-id"
    team_id          = "team-id"
    token            = "token"
  }
*/
}

resource "azurerm_notification_hub_authorization_rule" "rule1" {
  name                  = "management-auth-rule"
  notification_hub_name = azurerm_notification_hub.this.name
  namespace_name        = azurerm_notification_hub_namespace.this.name
  resource_group_name   = module.environment_resource_group.resource.name
  manage                = true
  send                  = true
  listen                = true
}

resource "azapi_resource_action" "comms-link-notification-hub" {
  type        = "Microsoft.Communication/communicationServices@2024-09-01-preview"
  resource_id = azurerm_communication_service.this.id
  action      = "linkNotificationHub"
  method      = "POST"

  body = {
    resourceId       = azurerm_notification_hub.this.id
    connectionString = azurerm_notification_hub_authorization_rule.rule1.primary_connection_string
  }

  depends_on = [
    azurerm_notification_hub.this,
    azurerm_notification_hub_authorization_rule.rule1,
    azurerm_communication_service.this
  ]
}

/*
resource "azurerm_monitor_diagnostic_setting" "comms_audit" {
  name                       = "Audit-${azurerm_communication_service.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_communication_service.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "audit"
  }
}
*/
/*
resource "azurerm_monitor_diagnostic_setting" "notification_hub_logs" {
  name                       = "Logs-Metrics-${azurerm_notification_hub.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_notification_hub.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
  enabled_metric {
    category = "AllMetrics"
  }
}
*/

output "comms_email_domain" {
  description = "The email domain for the Communication Service."
  sensitive   = false
  value       = azurerm_email_communication_service_domain.this.from_sender_domain
}

output "comms_email_sender_username" {
  description = "The email sender username for the Communication Service."
  sensitive   = false
  value       = azurerm_email_communication_service_domain_sender_username.this.name
}
