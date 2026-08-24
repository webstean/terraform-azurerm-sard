locals {
  swa_friendly_name      = "Static Web App"
  swa_name               = "sswa-${var.prefix}"
  swa_name_location      = "${local.swa_name}-${lower(var.location)}"
  swa_name_random_suffix = substr(md5(local.swa_name_location), 0, 6)
  swa_name_hostname      = lower(substr(replace("d${local.swa_name_random_suffix}${local.swa_name_location}", "-", ""), 0, 24))
  swa_sku_tier           = "Free"
  swa_sku_size           = "Free"
}

resource "azurerm_static_web_app" "this" {

  name                = local.swa_name
  resource_group_name = module.environment_resource_group.resource.name
  // only available in: westus2,centralus,eastus2,westeurope,eastasia,eastasiastage
  location = local.regions[azurerm_resource_group.environment.location].swa_location

  sku_tier                           = local.swa_sku_tier
  sku_size                           = local.swa_sku_size
  preview_environments_enabled       = true
  configuration_file_changes_enabled = true
  public_network_access_enabled      = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true

  dynamic "identity" {
    for_each = local.swa_sku_tier != "Free" ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.environment.id]
    }
  }

  /*
  app_settings {
    ## "WEBSITE_NODE_DEFAULT_VERSION" = "14.17.0"         
  }
*/

  /*
  basic_auth { ## cannot be used with free tier
    password     = "journey2024!X"
    environments = "AllEnvironments"
  }
*/

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

/*
resource "azurerm_monitor_diagnostic_setting" "swa1" {
  name                       = "Logs-${azurerm_static_web_app.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_static_web_app.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "allLogs"
  }
}
*/

output "swa_id" {
  description = "The ID of the Static Web App."
  sensitive   = false
  value       = azurerm_static_web_app.this.id
}

output "swa_url" {
  description = "The URL for the Static Web App site."
  sensitive   = false
  value       = "https://${azurerm_static_web_app.this.default_host_name}"
}

output "swa_repository_url" {
  description = "The repository URL of the Static Web App."
  sensitive   = false
  value       = azurerm_static_web_app.this.repository_url
}

output "swa_api_key" {
  description = "The API key of the Static Web App."
  sensitive   = true
  value       = azurerm_static_web_app.this.api_key
}

resource "local_file" "homepage" {
  filename = "${path.module}/site/index.html"
  content = templatefile("${path.module}/site/index.html.tftpl", {
    environment_name      = local.environment_name
    environment_home_page = local.environment_home_page
    portal_link           = local.portal_link
    owner_email           = var.owner_email
    location              = azurerm_resource_group.environment.location
  })
}

resource "terraform_data" "deploy_site" {
  triggers_replace = [
    timestamp() ## deploy every time, as the static web app does not support incremental deployments, without a dedicated CI/CD pipeline, so we need to redeploy the entire site every time.
  ]

  provisioner "local-exec" {
    command = <<-EOT
npx -y @azure/static-web-apps-cli --version
npx -y @azure/static-web-apps-cli deploy "${path.module}/site" --deployment-token "${azurerm_static_web_app.this.api_key}" --env production > swa-deploy.log 2>&1 || (cat swa-deploy.log; exit 1)
EOT
  }

  depends_on = [
    azurerm_static_web_app.this,
    local_file.homepage
  ]
}

output "static_web_app_url" {
  value = azurerm_static_web_app.this.default_host_name
}

