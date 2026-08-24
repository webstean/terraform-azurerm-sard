locals {
  lock_kind    = "CanNotDelete" // "CanNotDelete" or "ReadOnly"
  iac_message  = "Created and Managed by Terraform - no ClickOps! - use Terraform (IAC) instead"
  lock_message = "This resource is locked, due to it containing real PII or PHI data."

  cifs_mount_options = "dir_mode=0777,file_mode=0777,mfsymlinks,cache=strict,nosharesock,nobrl"
  nfs_mount_options  = "nconnect=4,noresvport,actimeo=30"

  ## use this instead of variable: var.location_key
  primary_region = local.regions["australiaeast"]

  ## use this instead of variable
  preferred_region = local.regions["australiaeast"]

  ## https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints
  storage_private_endpoints = toset(["blob", "dfs", "file", "queue", "table", "web"])
}

locals {
  default_cors = {
    allowed_methods = [
      "*",
    ],
    allowed_origins = [
      #        "https://${data.azuread_domains.root.domains.0.domain_name}",
      #        "https://*.${var.dns_zone_name}",
      "https://*.powerapps.com",
      "https://*.powerautomate.com",
      "https://*.azure.com",
    ],
  }
  secure_cors = {
    allowed_methods = [
      "*",
    ],
    allowed_origins = [
      "*",
      #        "https://${data.azuread_domains.root.domains.0.domain_name}",
      #        "https://*.${var.dns_zone_name}",
    ],
  }
}

locals {
  regions = {
    /*
    australiasoutheast = {
      // Freeform name - can be anything
      name               = "Melbourne"
      postcode           = "3000"
      short_name         = "mel"
      preferred_language = "en"
      country_code       = "AU"
      data_location      = "Australia"
      timezone           = "AUS Eastern Standard Time"
      ## for automation schedules
      time_zone_auto = "Australia/Sydney"

      // Offical Azure location (region)
      edge_zone                          = null
      long_name                          = "(Asia Pacific) Australia Southeast"
      region                             = "australiasoutheast"
      location                           = "australiasoutheast"
      location_shortname                 = "ase"
      zone_redundancy_available          = false
      zones                              = null
      default_rep_location               = "australiaeast"
      sql_maintenance_configuration_name = "SQL_AustraliaSouthEast_DB_1"
      ## Static Web Apps location - limited region support
      swa_location                    = "eastasia" ## "westus2", "centralus", "eastus2", "westeurope", "eastasia"
      devbox_pool_enabled             = false
      devbox_serverless_gpu_available = false

      // AWS
      aws_region_name = "ap-southeast-4"
      // Google Cloud
      gcp_region_name = "australia-southeast2"

      vnet_address_space = ["10.3.0.0/16"]
      ## The vWAN address prefix subnet cannot be smaller than a /24. Azure recommends using a /23.
      vwan_address_space = "10.3.1.0/24"
      ## Needs to be < 255 - use telephone area code
      location_number    = 3
      vnet_bgp_community = null ## The BGP community attribute in format <as-number>:<community-value>.

      dns_servers = null ## Azure Internal DNS - https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16

    }
*/

    australiaeast = { // needs to be the official Azure region name
      // Freeform name - can be anything
      name               = "Sydney"
      postcode           = "2000"
      short_name         = "syd"
      preferred_language = "en"
      country_code       = "AU"
      data_location      = "Australia"
      timezone           = "AUS Eastern Standard Time"
      ## for automation schedules
      time_zone_auto = "Australia/Sydney"

      // Offical Azure location (region)
      edge_zone                          = null
      long_name                          = "(Asia Pacific) Australia East"
      region                             = "australiaeast"
      location                           = "australiaeast"
      location_shortname                 = "ae"
      zone_redundancy_available          = true
      zones                              = [1, 2, 3]
      default_rep_location               = "australiasoutheast"
      sql_maintenance_configuration_name = "SQL_AustraliaEast_DB_1"
      ## Static Web Apps location - limited region support
      swa_location                    = "eastasia" ## "westus2", "centralus", "eastus2", "westeurope", "eastasia"
      devbox_pool_enabled             = true
      devbox_serverless_gpu_available = false

      // AWS
      aws_region_name = "ap-southeast-2"
      // Google Cloud
      gcp_region_name = "australia-southeast2"

      vnet_address_space = ["10.2.0.0/16"]
      ## The vWAN address prefix subnet cannot be smaller than a /24. Azure recommends using a /23.
      vwan_address_space = "10.2.1.0/24"
      ## Needs to be < 255 - use telephone area code
      location_number    = 2
      vnet_bgp_community = null ## The BGP community attribute in format <as-number>:<community-value>.

      dns_servers = null ## Azure Internal DNS - https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16

    }

    /*
    australiacentral = { // needs to be the official Azure region name
      // Freeform name - can be anything
      name               = "Canberra1"
      postcode           = "2600"
      short_name         = "can1"
      preferred_language = "en"
      country_code       = "AU"
      data_location      = "Australia"
      timezone           = "AUS Eastern Standard Time"
      ## for automation schedules
      time_zone_auto = "Australia/Sydney"

      // Offical Azure location (region)
      edge_zone                          = null
      long_name                          = "(Asia Pacific) Australia Central"
      region                             = "australiacentral"
      location                           = "australiacentral"
      location_shortname                 = "acl"
      zone_redundancy_available          = false
      zones                              = null
      default_rep_location               = "australiaeast"
      sql_maintenance_configuration_name = "SQL_AustraliaEast_DB_1"
      ## Static Web Apps location - limited region support
      swa_location                    = "eastasia" ## "westus2", "centralus", "eastus2", "westeurope", "eastasia"
      devbox_pool_enabled             = false
      devbox_serverless_gpu_available = false

      // AWS
      aws_region_name = null
      // Google Cloud
      gcp_region_name = null

      // vNet (free) with 7 subnets (free)
      vnet_address_space = ["10.22.0.0/16"]
      ## The vWAN address prefix subnet cannot be smaller than a /24. Azure recommends using a /23.
      vwan_address_space = "10.22.1.0/24"
      ## Needs to be < 255 - use telephone area code
      location_number    = 22
      vnet_bgp_community = null ## The BGP community attribute in format <as-number>:<community-value>.

      dns_servers = null ## Azure Internal DNS - https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16

      ##      lake_containers = local.lake_containers
    }
*/
    /*
    australiacentral2 = { // needs to be the official Azure region name
      // Freeform name - can be anything
      name         = "Canberra2"
      postcode      = "2600"
      short_name   = "can2"
      preferred_language = "en"
      country_code = "AU"
      data_location = "Australia"
      timezone = "AUS Eastern Standard Time"
      ## for automation schedules
      time_zone_auto = "Australia/Sydney"

      // Offical Azure location (region)
      edge_zone                          = null
      long_name          = "(Asia Pacific) Australia Central 2"
      region             = "australiacentral2"
      location           = "australiacentral2"
      location_shortname = "acl2"
      zone_redundancy_available          = false
      zones      = null
      default_rep_location = "australiaeast"
      sql_maintenance_configuration_name = "SQL_AustraliaEast_DB_1"
      ## Static Web Apps location - limited region support
      swa_location            = "eastasia" ## "westus2", "centralus", "eastus2", "westeurope", "eastasia"
      devbox_pool_enabled                = false
      devbox_serverless_gpu_available    = false

      // AWS
      aws_region_name = null
      // Google Cloud
      gcp_region_name = null

      vnet_address_space = ["10.222.0.0/16"]
      ## The vWAN address prefix subnet cannot be smaller than a /24. Azure recommends using a /23.
      vwan_address_space = "10.222.1.0/24"
      ## Needs to be < 255 - use telephone area code
      location_number = 3
      vnet_bgp_community       = null ## The BGP community attribute in format <as-number>:<community-value>.

      dns_servers        = null

    }
*/
    /*
    perth = { // needs to be the official Azure region name
      // Freeform name - can be anything
      name               = "Perth"
      postcode           = "6000"
      short_name         = "per"
      preferred_language = "en"
      country_code       = "AU"
      data_location      = "Australia"
      timezone           = "AUS Western Standard Time"
      ## for automation schedules
      time_zone_auto            = "Australia/Perth"

      // Offical Azure location (region)
      edge_zone                          = "perth"
      long_name                          = "(Asia Pacific) Australia East"
      region                             = "australiaeast"
      location                           = "australiaeast"
      location_shortname                 = "ae"
      zone_redundancy_available          = true
      zones                              = null
      default_rep_location               = "australiasoutheast"
      sql_maintenance_configuration_name = "SQL_AustraliaEast_DB_1"
      ## Static Web Apps location - limited region support
      swa_location = "eastasia" ## "westus2", "centralus", "eastus2", "westeurope", "eastasia"
      devbox_pool_enabled                = false
      devbox_serverless_gpu_available    = false

      // AWS
      aws_region_name = "ap-southeast-2"
      // Google Cloud
      gcp_region_name = "australia-southeast2"

      vnet_address_space = ["10.6.0.0/16"]
      ## The vWAN address prefix subnet cannot be smaller than a /24. Azure recommends using a /23.
      vwan_address_space = "10.6.1.0/24"
      ## Needs to be < 255 - use telephone area code
      location_number = 6
      vnet_bgp_community       = null ## The BGP community attribute in format <as-number>:<community-value>.

      dns_servers = null ## Azure Internal DNS - https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16

    }
*/

    centralindia = {
      // Freeform name - can be anything
      name               = "India"
      postcode           = "400001"
      short_name         = "ind"
      preferred_language = "en"
      country_code       = "IN"
      data_location      = "India"
      timezone           = "India Standard Time"
      ## for automation schedules
      time_zone_auto = "India/Mumbai"

      // Offical Azure location (region)
      edge_zone                          = null
      long_name                          = "(Asia Pacific) Central India"
      region                             = "centralindia"
      location                           = "centralindia"
      location_shortname                 = "ind"
      zone_redundancy_available          = false
      zones                              = null
      default_rep_location               = "southindia"
      sql_maintenance_configuration_name = "SQL_CentralIndia_DB_1"
      ## Static Web Apps location - limited region support
      swa_location                    = "eastasia" ## "westus2", "centralus", "eastus2", "westeurope", "eastasia"
      devbox_pool_enabled             = true
      devbox_serverless_gpu_available = false

      // AWS
      aws_region_name = "asia-northeast3"
      // Google Cloud
      gcp_region_name = "asia-south1"

      vnet_address_space = ["10.91.0.0/16"]
      ## The vWAN address prefix subnet cannot be smaller than a /24. Azure recommends using a /23.
      vwan_address_space = "10.91.1.0/24"
      ## Needs to be < 255 - use telephone area code
      location_number    = 91
      vnet_bgp_community = null ## The BGP community attribute in format <as-number>:<community-value>.

      dns_servers = null ## Azure Internal DNS - https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16

    }

    westus3 = {
      // Freeform name - can be anything
      name               = "WestUS3"
      postcode           = "90001"
      short_name         = "westus3"
      preferred_language = "en"
      country_code       = "US"
      data_location      = "United States"
      timezone           = "Pacific Standard Time"
      ## for automation schedules
      time_zone_auto = "America/Los_Angeles"

      // Offical Azure location (region)
      edge_zone                          = null
      long_name                          = "(US) West US 3"
      region                             = "westus3"
      location                           = "westus3"
      location_shortname                 = "wus3"
      zone_redundancy_available          = false
      zones                              = null
      default_rep_location               = null
      sql_maintenance_configuration_name = "SQL_WestUS3_DB_1"
      ## Static Web Apps location - limited region support
      swa_location                    = "eastasia" ## "westus2", "centralus", "eastus2", "westeurope", "eastasia"
      devbox_pool_enabled             = true
      devbox_serverless_gpu_available = false

      // AWS
      aws_region_name = "us-west-1"
      // Google Cloud
      gcp_region_name = "us-west2"

      vnet_address_space = ["10.213.0.0/16"]
      ## The vWAN address prefix subnet cannot be smaller than a /24. Azure recommends using a /23.
      vwan_address_space = "10.213.1.0/24"
      ## Needs to be < 255 - use telephone area code
      location_number    = 213
      vnet_bgp_community = null ## The BGP community attribute in format <as-number>:<community-value>.

      dns_servers = null ## Azure Internal DNS - https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16

    }
  }
}

locals {
  /*
  service_delegation = toset([
    "GitHub.Network/networkSettings",
    "Microsoft.ApiManagement/service",
    "Microsoft.Apollo/npu",
    "Microsoft.App/environments",
    "Microsoft.App/testClients",
    "Microsoft.AVS/PrivateClouds",
    "Microsoft.AzureCosmosDB/clusters",
    "Microsoft.BareMetal/AzurefpowerHostedService",
    "Microsoft.BareMetal/AzureHPC",
    "Microsoft.BareMetal/AzurePaymentHSM",
    "Microsoft.BareMetal/AzureVMware",
    "Microsoft.BareMetal/CrayServers",
    "Microsoft.BareMetal/MonitoringServers",
    "Microsoft.Batch/batchAccounts",
    "Microsoft.CloudTest/hostedpools",
    "Microsoft.CloudTest/images",
    "Microsoft.CloudTest/pools",
    "Microsoft.Codespaces/plans"
    "Microsoft.ContainerInstance/containerGroups",
    "Microsoft.ContainerService/managedClusters",
    "Microsoft.ContainerService/TestClients",
    "Microsoft.Databricks/workspaces",
    "Microsoft.DBforMySQL/flexibleServers",
    "Microsoft.DBforMySQL/servers",
    "Microsoft.DBforMySQL/serversv2",
    "Microsoft.DBforPostgreSQL/flexibleServers",
    "Microsoft.DBforPostgreSQL/serversv2",
    "Microsoft.DBforPostgreSQL/singleServers",
    "Microsoft.DelegatedNetwork/controller",
    "Microsoft.DevCenter/networkConnection",
    "Microsoft.DevOpsInfrastructure",
    "Microsoft.DocumentDB/cassandraClusters",
    "Microsoft.Fidalgo/networkSettings",
    "Microsoft.HardwareSecurityModules/dedicatedHSMs",
    "Microsoft.Kusto/clusters",
    "Microsoft.LabServices/labplans",
    "Microsoft.Logic/integrationServiceEnvironments",
    "Microsoft.MachineLearningServices/workspaces",
    "Microsoft.Netapp/volumes",
    "Microsoft.Network/dnsResolvers",
    "Microsoft.Network/managedResolvers",
    "Microsoft.Network/fpgaNetworkInterfaces",
    "Microsoft.Network/networkWatchers.",
    "Microsoft.Network/virtualNetworkGateways",
    "Microsoft.Orbital/orbitalGateways",
    "Microsoft.PowerPlatform/enterprisePolicies",
    "Microsoft.PowerPlatform/vnetaccesslinks",
    "Microsoft.ServiceFabricMesh/networks",
    "Microsoft.ServiceNetworking/trafficControllers",
    "Microsoft.Singularity/accounts/networks",
    "Microsoft.Singularity/accounts/npu",
    "Microsoft.Sql/managedInstances",
    "Microsoft.Sql/managedInstancesOnebox",
    "Microsoft.Sql/managedInstancesStage",
    "Microsoft.Sql/managedInstancesTest",
    "Microsoft.Sql/servers",
    "Microsoft.StoragePool/diskPools",
    "Microsoft.StreamAnalytics/streamingJobs",
    "Microsoft.Synapse/workspaces",
    "Microsoft.Web/hostingEnvironments",
    "Microsoft.Web/serverFarms",
    "NGINX.NGINXPLUS/nginxDeployments",
    "PaloAltoNetworks.Cloudngfw/firewalls",
    "Qumulo.Storage/fileSystems",
    "Oracle.Database/networkAttachments"
  ])
*/

  delegation-full-actions = toset([
    "Microsoft.Network/networkinterfaces/*",
    "Microsoft.Network/publicIPAddresses/join/action",
    "Microsoft.Network/publicIPAddresses/read",
    "Microsoft.Network/virtualNetworks/read",
    "Microsoft.Network/virtualNetworks/subnets/action",
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
    "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action",
  ])

  delegation-actions = toset([
    ##    "Microsoft.Network/networkinterfaces/*",
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    ##    "Microsoft.Network/virtualNetworks/subnets/action",
  ])

  service_endpoints = toset([
    "Microsoft.AzureActiveDirectory",
    "Microsoft.AzureCosmosDB",
    "Microsoft.CognitiveServices",
    "Microsoft.ContainerRegistry", // still in preview
    "Microsoft.EventHub",
    "Microsoft.KeyVault",
    "Microsoft.ServiceBus",
    "Microsoft.Storage", ## not supported when Microsoft.Storage.Global is in use
    ##"Microsoft.Storage.Global",
    "Microsoft.Sql",
    "Microsoft.Web",
  ])
}
