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

module "frontdoor" {
  source  = "Azure/avm-res-cdn-profile/azurerm"
  version = "0.1.9"
  count   = local.frontdoor_enabled ? 1 : 0

  location                 = module.environment_resource_group.resource.location
  name                     = local.frontdoor_name_location
  resource_group_name      = module.environment_resource_group.resource.name
  response_timeout_seconds = 30
  sku                      = var.frontdoor_sku == "Standard" ? "Standard_AzureFrontDoor" : "Premium_AzureFrontDoor"
  tags                     = module.environment_resource_group.resource.tags
  enable_telemetry         = var.enable_telemetry

  front_door_endpoints = {
    endpoint = {
      name = local.frontdoor_endpoint_name
    }
  }

  front_door_origin_groups = {
    origin_group = {
      name = local.frontdoor_origin_group_name
      load_balancing = {
        lb = {
          sample_size                 = 4
          successful_samples_required = 3
        }
      }
      health_probe = {
        hp = {
          path                = "/"
          request_type        = "HEAD"
          protocol            = "Https"
          interval_in_seconds = 120
        }
      }
    }
  }

  front_door_origins = {
    origin = {
      name                           = local.frontdoor_origin_name
      origin_group_key               = "origin_group"
      enabled                        = true
      certificate_name_check_enabled = true
      host_name                      = local.frontdoor_origin_host
      host_header                    = local.frontdoor_origin_host
      http_port                      = (tobool(var.data_pii) || tobool(var.data_phi)) ? 80 : 8080
      https_port                     = (tobool(var.data_pii) || tobool(var.data_phi)) ? 443 : 8443
      priority                       = 1
      weight                         = 1000
    }
  }

  front_door_custom_domains = {
    for alias in local.ingress_aliases_frontdoor : alias => {
      name      = "custom-domain-${alias}"
      host_name = "${alias}.${azurerm_dns_zone.environment.name}"
      tls = {
        certificate_type = "ManagedCertificate"
      }
    }
  }

  front_door_routes = {
    route = {
      name                   = local.frontdoor_route_name
      endpoint_key           = "endpoint"
      origin_group_key       = "origin_group"
      origin_keys            = [local.frontdoor_origin_name]
      custom_domain_keys     = [for alias in local.ingress_aliases_frontdoor : alias]
      enabled                = true
      forwarding_protocol    = "HttpsOnly"
      https_redirect_enabled = true
      link_to_default_domain = true
      patterns_to_match      = ["/*"]
      supported_protocols    = ["Http", "Https"]
    }
  }
  diagnostic_settings = var.logging_enabled == false ? null : {
    diag_setting_1 = {
      name       = "Optional Logging 1"
      log_groups = ["allLogs"]
      metric     = ["AllMetrics"]
      #metric_categories              = ["SLI", "Requests"]
      log_analytics_destination_type = null
      workspace_resource_id          = module.log_analytics_workspace.resource_id
    }
  }
  depends_on = [azurerm_dns_txt_record.frontdoor_swa_verify]
}

output "frontdoor_fqdn" {
  description = "The Front Door endpoint FQDN."
  sensitive   = false
  value       = try(module.frontdoor[0].frontdoor_endpoints["endpoint"].host_name, null)
}
output "frontdoor_txt_validation_token" {
  description = "The Front Door custom domain TXT validation token."
  sensitive   = false
  value       = try(module.frontdoor[0].frontdoor_custom_domains["fd"].validation_token, null)
}

