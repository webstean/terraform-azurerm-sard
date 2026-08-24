/*
## $$
resource "azurerm_dashboard_grafana" "grafana" {
  name                              = "graf-aca-aue"
  resource_group_name               = module.environment_resource_group.resource.name
  location                          = module.environment_resource_group.resource.location
  grafana_major_version             = "13"
  sku                               = "Standard"
  sku_size                          = "X1" ## X1 or X2
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true
  zone_redundancy_enabled           = false

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.this.id
  }

  # Optional SMTP configuration for Grafana alert notifications.
  # Uncomment and provide real values if SMTP is required.
  # smtp {
  #   enabled                   = true
  #   host                      = "smtp.example.net:587"
  #   user                      = "smtp-user"
  #   password                  = var.grafana_smtp_password
  #   start_tls_policy          = "MandatoryStartTLS"
  #   from_address              = "GRAFANA@${azurerm_email_communication_service_domain.this.name}"
  #   from_name                 = "Grafana Alerts"
  #   verification_skip_enabled = false
  # }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

resource "azurerm_role_assignment" "user_grafana_admin" {
  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = var.owner_entra_object_id
}
*/

