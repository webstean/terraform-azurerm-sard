locals {
  pep_name          = "pep-${var.prefix}"
  pep_name_location = lower("${local.pep_name}-${lower(var.location)}")
  pep_random_suffix = substr(md5(local.pep_name_location), 0, 6)
  pep_name_hostname = lower(substr(replace("l${local.pep_random_suffix}${local.pep_name_location}", "-", ""), 0, 24))
}

resource "azurerm_subnet" "private_endpoints" {
  count = tobool(var.deploy_private_endpoints) ? 1 : 1

  name                            = "private-endpoints"
  resource_group_name             = module.environment_resource_group.resource.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [format("10.%s.200.0/24", local.regions[var.location].location_number)]
  default_outbound_access_enabled = false

  service_endpoints                             = null
  private_link_service_network_policies_enabled = false
  ## Supported values: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled.
  private_endpoint_network_policies = "Enabled"
}

module "private_endpoint_sqlserver" {
  count = tobool(var.deploy_private_endpoints) ? 1 : 0

  source           = "Azure/avm-res-network-privateendpoint/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry # see variables.tf

  name                           = "${local.pep_name_location}-${azurerm_mssql_server.this.name}"
  resource_group_name            = module.environment_resource_group.resource.name
  location                       = module.environment_resource_group.resource.location
  network_interface_name         = "pep-${azurerm_mssql_server.this.name}"
  private_connection_resource_id = azurerm_mssql_server.this.id
  subnet_resource_id             = azurerm_subnet.private_endpoints[0].id
  subresource_names              = ["sqlServer"]
  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

/*
module "private_endpoint_keyvault" {
  count = tobool(var.deploy_private_endpoints) ? 1 : 0

  source           = "Azure/avm-res-network-privateendpoint/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry # see variables.tf

  name                           = "pep-${azurerm_key_vault.this.name}"
  resource_group_name            = module.environment_resource_group.resource.name
  location                       = module.environment_resource_group.resource.location
  network_interface_name         = "pep-${azurerm_key_vault.this.name}"
  private_connection_resource_id = azurerm_key_vault.this.id
  subnet_resource_id             = azurerm_subnet.private_endpoints[0].id
  subresource_names              = ["vault"]
  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags                           = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}
*/

locals {
  privatednszones = toset([
    #        "privatelink.azure-automation.net",
    "privatelink.database.windows.net",
    #        "privatelink.sql.azuresynapse.net",
    #        "privatelink.dev.azuresynapse.net",
    #        "privatelink.azuresynapse.net",
    ## Blob service
    "privatelink.blob.core.windows.net",
    ## Data Lake Storage Gen2
    "privatelink.dfs.core.windows.net",
    ## File service
    "privatelink.file.core.windows.net",
    ## Queue service
    "privatelink.queue.core.windows.net",
    ## Table service
    "privatelink.table.core.windows.net",
    ## Static Websites
    #"privatelink.web.core.windows.net",
    #        "privatelink.documents.azure.com",
    #        "privatelink.mongo.cosmos.azure.com",
    #        "privatelink.cassandra.cosmos.azure.com",
    #        "privatelink.gremlin.cosmos.azure.com",
    #        "privatelink.table.cosmos.azure.com",
    #        "privatelink.batch.azure.com",
    #        "privatelink.postgres.database.azure.com",
    #        "privatelink.mysql.database.azure.com",
    #        "privatelink.mariadb.database.azure.com",
    #        "privatelink.vaultcore.azure.net",
    #        "privatelink.managedhsm.azure.net",
    #        "privatelink.search.windows.net",
    #        "privatelink.azconfig.io",
    #        "privatelink.siterecovery.windowsazure.com",
    #        "privatelink.servicebus.windows.net",
    #        "privatelink.azure-devices.net",
    #        "privatelink.servicebus.windows.net",
    #        "privatelink.azure-devices-provisioning.net",
    #        "privatelink.eventgrid.azure.net",
    #"privatelink.azurewebsites.net",
    #        "scm.privatelink.azurewebsites.net",
    #        "privatelink.api.azureml.msprivatelink.notebooks.azure.net",
    #        "privatelink.service.signalr.net",
    #        "privatelink.monitor.azure.com",
    #        "privatelink.oms.opinsights.azure.com",
    #        "privatelink.ods.opinsights.azure.com",
    #        "privatelink.agentsvc.azure-automation.net",
    #        "privatelink.applicationinsights.azure.com",
    #        "privatelink.cognitiveservices.azure.com",
    #        "privatelink.openai.azure.com",
    #        "privatelink.datafactory.azure.net",
    #        "privatelink.adf.azure.com",
    #        "privatelink.redis.cache.windows.net",
    #        "privatelink.redisenterprise.cache.azure.net",
    #        "privatelink.purview.azure.com",
    #        "privatelink.purviewstudio.azure.com",
    #        "privatelink.digitaltwins.azure.net",
    #        "privatelink.azurehdinsight.net",
    #        "privatelink.his.arc.azure.com",
    #        "privatelink.guestconfiguration.azure.com",
    #        "privatelink.kubernetesconfiguration.azure.com",
    #        "privatelink.media.azure.net",
    #        "privatelink.prod.migration.windowsazure.com",
    #        "privatelink.azure-api.net",
    #        "privatelink.developer.azure-api.net",
    #        "privatelink.analysis.windows.net",
    #        "privatelink.pbidedicated.windows.net",
    #        "privatelink.tip1.powerquery.microsoft.com",
    #        "privatelink.directline.botframework.com",
    #        "privatelink.token.botframework.com",
    #        "privatelink.workspace.azurehealthcareapis.com",
    #        "privatelink.fhir.azurehealthcareapis.com",
    #        "privatelink.dicom.azurehealthcareapis.com",
    #        "privatelink.azuredatabricks.net",
  ])
}

## data.azurerm_subscription.current.display_name

resource "azurerm_private_dns_zone" "privatelink-dns1" {
  for_each = tobool(var.deploy_private_endpoints) ? toset(local.privatednszones) : toset([])

  name                = lower(each.value)
  resource_group_name = module.environment_resource_group.resource.name

  soa_record {
    email = "hostmaster.${each.value}"
    ttl   = 3600
    tags  = local.dns_tags_private
  }
  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

## region specific DNS privatelink zones
#resource "azurerm_private_dns_zone" "privatelink-dns2" {
#  for_each = tobool(var.deploy_private_endpoints) ? toset(local.privatednszones) : toset([])
#
#  name                = format("%s.%s.%s", "privatelink", each.value.location, "backup.windowsazure.com")
#  resource_group_name = module.environment_resource_group.resource.name
#  soa_record {
#    email = "hostmaster.${data.azuread_domains.admin.domains[0].domain_name}"
#    ttl   = 3600
#    tags  = local.dns_tags_private
#  }
#  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
#}

#resource "azurerm_private_dns_zone" "privatelink-dns3" {
#  for_each = tobool(var.deploy_private_endpoints) ? toset(local.regions) : toset([])
#
#  name                = format("%s%s.%s", "privatelink.azurecr.io", each.value.location, "privatelink.azurecr.io")
#  resource_group_name = module.environment_resource_group.resource.name
#  soa_record {
#    email = "hostmaster.${data.azuread_domains.admin.domains[0].domain_name}"
#    ttl   = 3600
#    tags  = local.dns_tags_private
#  }
#  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
#}

#resource "azurerm_private_dns_zone" "privatelink-dns4" {
#  for_each = tobool(var.deploy_private_endpoints) ? toset(local.regions) : toset([])
#
#  name                = format("%s.%s", each.value.location, "privatelink.afs.azure.net")
#  resource_group_name = module.environment_resource_group.resource.name
#  soa_record {
#    email = "hostmaster.${data.azuread_domains.admin.domains[0].domain_name}"
#    ttl   = 3600
#    tags  = local.dns_tags_private
#  }
#  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
#}

## Eg. "privatelink.australiaeast.kusto.windows.net",
#resource "azurerm_private_dns_zone" "privatelink-dns5" {
#  for_each = tobool(var.deploy_private_endpoints) ? toset(local.regions) : toset([])
#  
#  name                = format("%s.%s.%s", "privatelink", each.value.location, "kusto.windows.net")
#  resource_group_name = module.environment_resource_group.resource.name
#  soa_record {
#    email = "hostmaster.${data.azuread_domains.admin.domains[0].domain_name}"
#    ttl   = 3600
#    tags  = local.dns_tags_private
#  }
#  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
#}
