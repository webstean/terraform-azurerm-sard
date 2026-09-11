locals {
  frontdoor_friendly_name        = "Front Door"
  frontdoor_name                 = "frontdoor-${var.prefix}"
  frontdoor_name_location        = "${local.frontdoor_name}-${lower(var.location)}"
  frontdoor_name_random_suffix   = substr(md5(local.frontdoor_name_location), 0, 6)
  frontdoor_name_hostname        = lower(substr(replace("d${local.frontdoor_name_random_suffix}${local.frontdoor_name_location}", "-", ""), 0, 24))
  frontdoor_endpoint_name        = "fde-${local.frontdoor_name_hostname}"
  frontdoor_origin_group_name    = "og-${local.frontdoor_name_hostname}"
  frontdoor_origin_name          = "origin-${local.frontdoor_name_hostname}"
  frontdoor_route_name           = "route-${local.frontdoor_name_hostname}"
  frontdoor_dns_name             = try(trimspace(var.custom_dns_zone_name), "")
  frontdoor_enabled              = tobool(var.inbound_access == "FrontDoor" && local.frontdoor_dns_name != "")
  frontdoor_origin_host          = trimsuffix(replace(replace(local.frontdoor_dns_name, "https://", ""), "http://", ""), "/")
  frontdoor_custom_dns_zone_name = "cd-${substr(local.frontdoor_name_hostname, 0, 18)}"
}

resource "azurerm_cdn_frontdoor_profile" "this" {
  count = local.frontdoor_enabled ? 1 : 0

  name                = local.frontdoor_name_location
  resource_group_name = module.environment_resource_group.resource.name
  sku_name            = var.frontdoor_sku == "Standard" ? "Standard_AzureFrontDoor" : "Premium_AzureFrontDoor"

  response_timeout_seconds = 30
  tags                     = module.environment_resource_group.resource.tags
  lifecycle {
    ignore_changes = [tags.created]
  }
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  count = local.frontdoor_enabled ? 1 : 0

  name                     = local.frontdoor_endpoint_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this[0].id
  enabled                  = true
}

resource "azurerm_cdn_frontdoor_origin_group" "this" {
  count = local.frontdoor_enabled ? 1 : 0

  name                     = local.frontdoor_origin_group_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this[0].id

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }

  health_probe {
    path                = "/"
    request_type        = "HEAD"
    protocol            = "Https"
    interval_in_seconds = 120
  }
}

resource "azurerm_cdn_frontdoor_origin" "this" {
  count = local.frontdoor_enabled ? 1 : 0

  name                          = local.frontdoor_origin_name
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this[0].id

  enabled                        = true
  certificate_name_check_enabled = true
  host_name                      = local.frontdoor_origin_host
  origin_host_header             = local.frontdoor_origin_host
  ## Only supported  HTTP ports:  80, 8080
  http_port = (tobool(var.data_pii) || tobool(var.data_phi)) ? 80 : 8080
  ## Only supported  HTTPS ports:  443, 8443
  https_port = (tobool(var.data_pii) || tobool(var.data_phi)) ? 443 : 8443
  priority   = 1
  weight     = 1000
}

resource "azurerm_cdn_frontdoor_route" "this" {
  count = local.frontdoor_enabled ? 1 : 0

  name                          = local.frontdoor_route_name
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this[0].id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this[0].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.this[0].id]
  ## certificate
  cdn_frontdoor_custom_domain_ids = [
    try(azurerm_cdn_frontdoor_custom_domain.this["fd"].id, null)
  ]

  enabled                = true
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]
}

/*
resource "azurerm_monitor_diagnostic_setting" "frontdoor_logs" {
  count = local.frontdoor_enabled ? 1 : 0

  name                       = "Audit-and-Logs-${azurerm_cdn_frontdoor_profile.this[0].name}-to-Azure-Monitor"
  target_resource_id         = azurerm_cdn_frontdoor_profile.this[0].id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "audit"
  }
  enabled_log {
    category_group = "allLogs"
  }
}
resource "azurerm_monitor_diagnostic_setting" "frontdoor_metrics" {
  count = local.frontdoor_enabled ? 1 : 0

  name                       = "Metrics-${azurerm_cdn_frontdoor_profile.this[0].name}-to-Azure-Monitor"
  target_resource_id         = azurerm_cdn_frontdoor_profile.this[0].id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
*/
/*
output "frontdoor_fqdn" {
  description = "The Front Door endpoint FQDN."
  sensitive   = false
  value       = try(azurerm_cdn_frontdoor_endpoint.this[0].host_name, null)
}
output "frontdoor_txt_validation_token" {
  description = "The Front Door custom domain TXT validation token."
  sensitive   = false
  value       = try(azurerm_cdn_frontdoor_custom_domain.this["fd"].validation_token, null)
}
*/

