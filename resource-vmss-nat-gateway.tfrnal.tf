locals {
  nat_friendly_name     = "NAT Gateway"
  nat_name              = var.prefix
  nat_name_location     = lower("${local.nat_name}-${lower(var.location)}")
  nat_random_suffix     = substr(random_string.environment.result, 0, 6)
  nat_name_hostname     = lower(substr(replace("l${local.nat_random_suffix}${local.nat_name_location}", "-", ""), 0, 24))
  nat_gateway_pip_count = (tobool(var.data_pii) || tobool(var.data_phi)) ? 3 : 1
  nat_gateway_pip_keys = toset([
    for i in range(local.nat_gateway_pip_count) : format("pip%02d", i + 1)
  ])
  nat_gateway_pips = {
    for i in range(local.nat_gateway_pip_count) :
    format("pip%02d", i + 1) => {
      name = "pip-natgw-${format("%02d", i + 1)}-${var.location}"
    }
  }
}

module "nat_gateway" {
  count = var.deploy_nat_gateway ? 1 : 0

  source           = "Azure/avm-res-network-natgateway/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry

  name      = "nat-${local.nat_name_location}"
  parent_id = module.environment_resource_group.resource.id
  location  = module.environment_resource_group.resource.location
  sku_name  = "StandardV2"

  public_ips = local.nat_gateway_pips

  public_ip_configuration = {
    main = {
      allocation_method       = "Static"
      idle_timeout_in_minutes = 30
      ip_version              = "IPv4"
      sku                     = "StandardV2"
      sku_tier                = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? "Global" : "Regional"
      zones                   = local.regions[var.location].zones
    }
  }
  /*
  ## doesn't work - timesout after 30mins trying to create
  diagnostic_settings = var.logging_enabled == false ? null : {
    diagsettings = {
      name                           = "Optional NAT Gateway Logging 1"
      log_groups                     = ["allLogs"]
      metric                         = ["AllMetrics"]
      log_analytics_destination_type = null
      workspace_resource_id          = module.log_analytics_workspace.resource_id
    }
  }
*/
  lock = (tobool(var.data_pii) || tobool(var.data_phi)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

locals {
  vmss_external_load_balancer_pip_count      = (tobool(var.data_pii) || tobool(var.data_phi)) ? 3 : 1
  vmss_external_load_balancer_probe_protocol = "Tcp"
}

resource "azurerm_public_ip" "vmss_external" {
  for_each = var.deploy_vmss_external_load_balancer ? {
    for index in range(local.vmss_external_load_balancer_pip_count) : format("pip%02d", index + 1) => index + 1
  } : {}

  name = "pip-vmss-external-${format("%02d", each.value)}"
  ## parent_id = module.environment_resource_group.resource.id
  resource_group_name     = module.environment_resource_group.resource.name
  location                = module.environment_resource_group.resource.location
  allocation_method       = "Static"
  domain_name_label       = local.vmss_external_load_balancer_pip_count == 1 ? "${local.vmss_name}${random_string.environment.result}" : "${local.vmss_name}${random_string.environment.result}-${format("%02d", each.value)}"
  idle_timeout_in_minutes = 30
  ip_version              = "IPv4"
  sku                     = "Standard"
  sku_tier                = "Regional"
  zones                   = contains(local.regions[var.location].zones, "None") ? null : local.regions[var.location].zones
  tags                    = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }

  lifecycle {
    create_before_destroy = true
  }
}

module "vmss_external_load_balancer" {
  count = var.deploy_vmss_external_load_balancer ? 1 : 0

  source           = "Azure/avm-res-network-loadbalancer/azurerm"
  version          = "~>0.5, < 1.0"
  enable_telemetry = var.enable_telemetry

  name      = "lb-external-${local.vmss_name}"
  parent_id = module.environment_resource_group.resource.id
  ## resource_group_name = module.environment_resource_group.resource.name
  location = module.environment_resource_group.resource.location
  sku      = "Standard"
  sku_tier = "Regional" # Global-tier backends must be regional load balancers, not VMSS NICs.

  frontend_ip_configurations = {
    for index in range(local.vmss_external_load_balancer_pip_count) :
    format("vmss_frontend_%02d", index + 1) => {
      name                          = format("vmss-external-frontend-%02d", index + 1)
      public_ip_address_resource_id = azurerm_public_ip.vmss_external[format("pip%02d", index + 1)].id
      ## Azure rejects zones on a frontend config that references a public IP; zones come from the public IP itself.
      zones = ["None"]
    }
  }

  backend_address_pools = {
    vmss = {
      name = "vmss-backend-pool"
    }
  }

  lb_rules = {
    for index in range(local.vmss_external_load_balancer_pip_count) :
    format("vmss_rule_%02d", index + 1) => {
      name                              = format("vmss-rule-%02d", index + 1)
      frontend_ip_configuration_name    = format("vmss-external-frontend-%02d", index + 1)
      protocol                          = "Tcp"
      frontend_port                     = var.vmss_port_tcp_external
      backend_port                      = var.vmss_port_tcp_internal
      backend_address_pool_object_names = ["vmss"]
      probe_object_name                 = "vmss"
      load_distribution                 = "SourceIPProtocol"
      enable_floating_ip                = true # Required for backend-port reuse; guest loopback configuration is documented in README.md.
      disable_outbound_snat             = var.deploy_nat_gateway
    }
  }

  lb_probes = {
    vmss = {
      name     = "vmss-health-probe"
      protocol = local.vmss_external_load_balancer_probe_protocol
      port     = var.vmss_port_tcp_internal_probe
      #request_path = "/index.html" only for HTTP/HTTPS probes
    }
  }

  /*
diagnostic_settings = var.logging_enabled == false ? null : {
    diagsettings = {
      name                           = "Optional NLB Logging 1"
      log_groups                     = ["allLogs"]
      metric_categories              = ["AllMetrics"]
      # log_analytics_destination_type = null
      workspace_resource_id          = module.log_analytics_workspace.resource_id
    }
  }
*/

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}
