locals {
  relay_name          = "relay-${var.prefix}"
  relay_name_location = lower("${local.relay_name}-${lower(var.location)}")
  relay_random_suffix = substr(md5(local.relay_name_location), 0, 6)
  relay_name_hostname = lower(substr(replace("l${local.relay_random_suffix}${local.relay_name_location}", "-", ""), 0, 24))
  relay_port          = 1433 ## sql server
}

resource "azurerm_public_ip" "relay" {
  count = tobool(var.deploy_private_endpoints) ? 1 : 0

  name                = "pip-${local.relay_name}"
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

resource "azurerm_lb" "relay" {
  count = tobool(var.deploy_private_endpoints) ? 1 : 0

  name                = "lb-tcp-relay"
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "public-frontend"
    public_ip_address_id = azurerm_public_ip.relay[0].id
  }
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

# IP-based backend pool: points at a private IP directly, no NIC/VM
# association required. Needs the VNet ID so the LB knows how to route.
resource "azurerm_lb_backend_address_pool" "relay" {
  count = tobool(var.deploy_private_endpoints) ? 1 : 0

  name            = "backend-private-target"
  loadbalancer_id = azurerm_lb.relay[0].id
}

resource "azurerm_lb_backend_address_pool_address" "target" {
  count = tobool(var.deploy_private_endpoints) ? 1 : 0

  name                    = "target-ip"
  backend_address_pool_id = azurerm_lb_backend_address_pool.relay[0].id
  virtual_network_id      = azurerm_virtual_network.this.id

  # the private IP you're relaying to
  ip_address = module.private_endpoint_sqlserver[0].resource.private_service_connection[0].private_ip_address
}

resource "azurerm_lb_probe" "tcp" {
  count = tobool(var.deploy_private_endpoints) ? 1 : 0

  name            = "tcp-probe-port-${local.relay_port}"
  loadbalancer_id = azurerm_lb.relay[0].id
  protocol        = "Tcp"
  port            = local.relay_port
}

resource "azurerm_lb_rule" "relay" {
  count = tobool(var.deploy_private_endpoints) ? 1 : 0

  name                           = "tcp-${local.relay_port}"
  loadbalancer_id                = azurerm_lb.relay[0].id
  protocol                       = "Tcp"
  frontend_port                  = local.relay_port
  backend_port                   = local.relay_port
  frontend_ip_configuration_name = "public-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.relay[0].id]
  probe_id                       = azurerm_lb_probe.tcp[0].id
}

output "relay_public_ip" {
  description = "The public IP address of the relay load balancer."
  sensitive   = false
  value       = try(azurerm_public_ip.relay[0].ip_address, null)
}

