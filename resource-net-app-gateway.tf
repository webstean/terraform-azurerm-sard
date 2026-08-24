locals {
  gateway_friendly_name = "Application Gateway"
  gateway_name          = "gateway-${var.prefix}"
  gateway_name_location = lower("${local.gateway_name}-${lower(var.location)}")
  gateway_random_suffix = substr(md5(local.gateway_name_location), 0, 6)
  gateway_name_hostname = lower(substr(replace("l${local.gateway_random_suffix}${local.gateway_name_location}", "-", ""), 0, 24))
}

locals {
  app_gateway_public_ip_name                 = "pip-${local.gateway_name_location}"
  app_gateway_frontend_ip_configuration_name = "feip-${local.gateway_name_location}"
  app_gateway_frontend_port_name             = "feport-${local.gateway_name_location}"
  app_gateway_frontend_tls_port_name         = "feporttls-${local.gateway_name_location}"
  app_gateway_backend_address_pool_name      = "beap-${local.gateway_name_location}"
  app_gateway_backend_fqdn                   = try(trimspace(var.custom_dns_zone_name), "")
  app_gateway_http_setting_name              = "be-htst-${local.gateway_name_location}"
  app_gateway_probe_name                     = "probe-${local.gateway_name_location}"
  app_gateway_http_listener_name             = "httplstn-${local.gateway_name_location}"
  app_gateway_https_listener_name            = "httpslstn-${local.gateway_name_location}"
  app_gateway_ssl_certificate_name           = "sslcert-${substr(local.gateway_name_location, 0, 16)}"
  app_gateway_tls_enabled                    = local.app_gateway_backend_fqdn != ""
  app_gateway_request_routing_rule_name      = "rqrt-https-${local.gateway_name_location}"
  app_gateway_http_redirect_rule_name        = "rqrt-http-redirect-${local.gateway_name_location}"
  app_gateway_redirect_configuration_name    = "rdrcfg-${local.gateway_name_location}"
}

resource "azurerm_subnet" "app_gateway" {
  count = var.inbound_access == "App-Gateway" ? 1 : 0

  name                                          = "ApplicationGatewaySubnet"
  resource_group_name                           = module.environment_resource_group.resource.name
  virtual_network_name                          = azurerm_virtual_network.this.name
  address_prefixes                              = [format("10.%s.66.0/24", local.regions[var.location].location_number)]
  default_outbound_access_enabled               = false
  service_endpoints                             = var.deploy_private_endpoints ? null : local.service_endpoints
  private_link_service_network_policies_enabled = true
  ## Supported values: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled.
  ## Keep this as Enabled so private endpoint network policies remain active on this subnet unless a workload explicitly requires policy exemptions.
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_public_ip" "app_gateway" {
  count = var.inbound_access == "App-Gateway" ? 1 : 0

  name                = local.app_gateway_public_ip_name
  resource_group_name = module.environment_resource_group.resource.name
  location            = azurerm_resource_group.environment.location
  allocation_method   = "Static"

  tags       = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
  depends_on = [azurerm_role_assignment.sql_kv_admin]
}

/*
resource "azurerm_monitor_diagnostic_setting" "gateway_pip_metrics" {
  count = var.inbound_access == "App-Gateway" ? 1 : 0

  name                       = "Metrics-${azurerm_public_ip.app_gateway[0].name}-to-Azure-Monitor"
  target_resource_id         = azurerm_public_ip.app_gateway[0].id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
resource "azurerm_monitor_diagnostic_setting" "gateway_pip_logs" {
  count = var.inbound_access == "App-Gateway" ? 1 : 0

  name                       = "Logs-${azurerm_public_ip.app_gateway[0].name}-to-Azure-Monitor"
  target_resource_id         = azurerm_public_ip.app_gateway[0].id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
}
*/


resource "azurerm_web_application_firewall_policy" "gateway" {
  count = var.inbound_access == "App-Gateway" ? 1 : 0

  name                = "wafp-${local.gateway_name_location}"
  resource_group_name = module.environment_resource_group.resource.name
  location            = azurerm_resource_group.environment.location

  policy_settings {
    enabled                                   = true
    js_challenge_cookie_expiration_in_minutes = 5
    max_request_body_size_in_kb               = 128
    file_upload_limit_in_mb                   = 200
    mode                                      = "Prevention"
    request_body_check                        = true
    request_body_inspect_limit_in_kb          = 128
    file_upload_enforcement                   = true
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

resource "azurerm_application_gateway" "this" {
  count = var.inbound_access == "App-Gateway" ? 1 : 0

  name                = local.gateway_name_location
  resource_group_name = module.environment_resource_group.resource.name
  location            = azurerm_resource_group.environment.location
  firewall_policy_id  = azurerm_web_application_firewall_policy.gateway[0].id

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.environment.id
    ]
  }

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 1
    max_capacity = 2
  }

  gateway_ip_configuration {
    name      = local.app_gateway_frontend_port_name
    subnet_id = azurerm_subnet.app_gateway[0].id
  }

  frontend_port {
    name = local.app_gateway_frontend_port_name
    port = 80
  }

  frontend_port {
    name = local.app_gateway_frontend_tls_port_name
    port = 443
  }

  frontend_ip_configuration {
    name                 = local.app_gateway_frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.app_gateway[0].id
  }

  dynamic "ssl_certificate" {
    for_each = local.app_gateway_tls_enabled ? [1] : []
    content {
      name                = local.app_gateway_ssl_certificate_name
      key_vault_secret_id = azurerm_key_vault_certificate.letsencrypt-this[0].secret_id
    }
  }

  backend_address_pool {
    name  = local.app_gateway_backend_address_pool_name
    fqdns = local.app_gateway_backend_fqdn == "" ? [] : [local.app_gateway_backend_fqdn]
  }

  backend_http_settings {
    name                                = local.app_gateway_http_setting_name
    cookie_based_affinity               = "Disabled"
    path                                = "/"
    port                                = 443
    protocol                            = "Https"
    pick_host_name_from_backend_address = true
    request_timeout                     = 60
    probe_name                          = local.app_gateway_probe_name
  }

  probe {
    name                                      = local.app_gateway_probe_name
    protocol                                  = "Https"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-399"]
    }
  }

  http_listener {
    name                           = local.app_gateway_http_listener_name
    frontend_ip_configuration_name = local.app_gateway_frontend_ip_configuration_name
    frontend_port_name             = local.app_gateway_frontend_port_name
    protocol                       = "Http"
  }

  dynamic "http_listener" {
    for_each = local.app_gateway_tls_enabled ? [1] : []
    content {
      name                           = local.app_gateway_https_listener_name
      frontend_ip_configuration_name = local.app_gateway_frontend_ip_configuration_name
      frontend_port_name             = local.app_gateway_frontend_tls_port_name
      protocol                       = "Https"
      ssl_certificate_name           = local.app_gateway_ssl_certificate_name
    }
  }

  dynamic "redirect_configuration" {
    for_each = local.app_gateway_tls_enabled ? [1] : []
    content {
      name                 = local.app_gateway_redirect_configuration_name
      redirect_type        = "Permanent"
      target_listener_name = local.app_gateway_https_listener_name
      include_path         = true
      include_query_string = true
    }
  }

  request_routing_rule {
    name                       = local.app_gateway_request_routing_rule_name
    priority                   = 9
    rule_type                  = "Basic"
    http_listener_name         = local.app_gateway_tls_enabled ? local.app_gateway_https_listener_name : local.app_gateway_http_listener_name
    backend_address_pool_name  = local.app_gateway_backend_address_pool_name
    backend_http_settings_name = local.app_gateway_http_setting_name
  }

  dynamic "request_routing_rule" {
    for_each = local.app_gateway_tls_enabled ? [1] : []
    content {
      name                        = local.app_gateway_http_redirect_rule_name
      priority                    = 8
      rule_type                   = "Basic"
      http_listener_name          = local.app_gateway_http_listener_name
      redirect_configuration_name = local.app_gateway_redirect_configuration_name
    }
  }

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

/*
resource "azurerm_monitor_diagnostic_setting" "gateway_metrics" {
  count = var.inbound_access == "App-Gateway" ? 1 : 0

  name                       = "Metrics-${azurerm_application_gateway.this[0].name}-to-Azure-Monitor"
  target_resource_id         = azurerm_application_gateway.this[0].id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
resource "azurerm_monitor_diagnostic_setting" "gateway_logs" {
  count = var.inbound_access == "App-Gateway" ? 1 : 0

  name                       = "Logs-${azurerm_application_gateway.this[0].name}-to-Azure-Monitor"
  target_resource_id         = azurerm_application_gateway.this[0].id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
}
*/

