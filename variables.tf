
variable "customer" {
  type        = string
  description = "The name of the customer (free-text)"
  default     = "andrew"
}

variable "prefix" {
  type        = string
  description = "The short name of the customer - used for naming Azure resources."
  default     = "jit"
}

variable "location" {
  type        = string
  description = "The Azure region where resources will be deployed."
  default     = "australiaeast"

  validation {
    condition     = contains(["australiasoutheast", "australiaeast", "australiacentral", "australiacentral2", "perth", "centralindia", "westus3"], lower(trimspace(var.location)))
    error_message = "location must be one of the currently known Azure regions defined in locals.regions."
  }
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription ID in which the resources will be deployed."
  default     = "3fdbf472-cbf2-43ca-9f61-3c34bdc1397c"

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", trimspace(var.subscription_id)))
    error_message = "subscription_id must be a valid GUID."
  }
}

variable "alert_email" {
  type        = string
  description = "The email address for alerts"
  default     = "webstean@gmail.com"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", trimspace(var.alert_email)))
    error_message = "The variable 'alert_email' must be a valid email address."
  }
}

variable "owner_email" {
  type        = string
  description = "The email address for the owner of the environment"
  default     = "Andrew.Webster@unisys.com"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", trimspace(var.owner_email)))
    error_message = "The variable 'owner_email' must be a valid email address."
  }
}

variable "owner_entra_object_id" {
  type        = string
  description = "The Entra ID object ID for the owner of this environment"
  default     = "6acb0d56-1549-40f0-b90e-170dcd10674a"

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", trimspace(var.owner_entra_object_id)))
    error_message = "The variable 'owner_entra_object_id' must be a valid GUID."
  }
}
variable "owner_entra_display_name" {
  type        = string
  description = "The Entra ID display name for the owner of this environment"
  default     = "Webster, Andrew"
}

variable "sql_administrator_group_object_id" {
  type        = string
  description = "The Entra ID object ID for the SQL administrator group (can be a user or a group)"
  default     = "b01746a3-ab71-4d5c-baee-44708bb11b0d"

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", trimspace(var.sql_administrator_group_object_id)))
    error_message = "The variable 'sql_administrator_group_object_id' must be a valid GUID."
  }
}
variable "sql_administrator_group_display_name" {
  type        = string
  description = "The Entra ID display name for the SQL administrators (can be a user or a group)"
  default     = "DWS Professional Services"
}

variable "alert_sms_country" {
  type        = string
  description = "The country code for SMS alerts"
  default     = "+61"
}

variable "alert_sms_number" {
  type        = string
  description = "The phone number for SMS alerts"
  default     = "490846099"
}

variable "security_perimeter_inbound_public_ips" {
  type        = list(string)
  description = "Allowed inbound addresses for the Azure Security Perimeter."
  default     = ["0.0.0.0/0"]
}

variable "security_perimeter_outbound_fqdns" {
  type        = list(string)
  description = "Allowed outbound FQDNs for the Azure Security Perimeter."
  default     = ["*"]
}


variable "vmss_number_of_instances" {
  type        = number
  description = "The number of instances in the Virtual Machine Scale Set."
  default     = 0 ## Anything but zero, cost money :-)
}

variable "vmss_autoscale_enabled" {
  description = "Whether autoscale is enabled for the Virtual Machine Scale Set."
  type        = bool
  default     = true
}

variable "bastion_sku" {
  type    = string
  default = "Developer"

  ## https://learn.microsoft.com/en-us/azure/bastion/bastion-sku-comparison
  validation {
    condition = (
      contains(["Developer", "Basic", "Standard", "Premium"], var.bastion_sku)
    )
    error_message = "The variable 'bastion_sku' must be one of: Developer, Basic, Standard, Premium."
  }
}

// +===========================================================================================================+

variable "enable_telemetry" {
  type        = bool
  description = <<DESCRIPTION
This variable controls whether or not the AVM (Azure Verified Modules) telemetry is enabled for the module.
For more information see <https://aka.ms/avm/telemetryinfo>.
If it is set to false, then no telemetry will be collected.
DESCRIPTION  
  default     = false
}

variable "data_pii" {
  type        = bool
  description = "If true, this environment contains PII (Personally Identifiable Information) so deploy additional security controls. If false, deploys a non-PII environment."
  default     = false
}

variable "data_phi" {
  type        = bool
  description = "If true, this environment contains PHI (Protected Health Information) so deploy additional security controls. If false, deploys a non-PHI environment."
  default     = false
}

variable "deploy_sql_failover" {
  type        = bool
  description = "If true, deploys a Microsoft SQL failover environment in the linked region. If false, deploys a single SQL instance."
  default     = false
}

variable "support_free_sql_database" {
  type        = bool
  description = "If true, support the totally Free SQL Server. Failover must be disabled and the SQL Server cannot have an alias."
  default     = true
  validation {
    condition     = !var.support_free_sql_database || !var.deploy_sql_failover
    error_message = "The variable 'support_free_sql_database' can only be true when 'deploy_sql_failover' is false."
  }
}

## not implemented - yet
variable "sql_connectivity_type" {
  type        = string
  description = "Connectivity mode for the SQL Server endpoint: PRIVATE (VNet via Private Endpoint), or PUBLIC (internet-facing)."
  default     = "PRIVATE"

  validation {
    condition     = contains(["PRIVATE", "PUBLIC"], var.sql_connectivity_type)
    error_message = "sql_connectivity_type must be one of 'PRIVATE' or 'PUBLIC'."
  }
}

variable "deploy_private_endpoints" {
  type        = bool
  description = "If true, deploys private endpoints for secure access to Azure services. If false, does not deploy private endpoints."
  default     = false
}

variable "inbound_access" {
  type        = string
  description = "Specifies the type of inbound access to the environment via the Internet. Options are: 'None' (free), 'App-Gateway' ($$), 'FrontDoor' ($$)."
  default     = "None"

  validation {
    condition = (
      contains(["None", "App-Gateway", "FrontDoor"], var.inbound_access)
    )
    error_message = "The variable 'inbound_access' must be one of: None, App-Gateway, FrontDoor."
  }
}

variable "outbound_access" {
  type        = string
  description = <<DESC
Specifies the type of outbound access to the environment via the Internet. Options are: 'Direct' (free), 'Nat-Gateway' ($$), 'Hub-and-Spoke-with-Nat-Gateway' ($$$).
Note: that 'Direct' does not allowed Virtual Machine Scale Sets to have any OutBound Internet access, you need to use a Nat-Gateway or Hub-and-Spoke
DESC
  default     = "Direct"

  validation {
    condition = (
      contains(["Direct", "Nat-Gateway", "Hub-and-Spoke-with-Nat-Gateway"], var.outbound_access)
    )
    error_message = "The variable 'outbound_access' must be one of: 'Direct', 'Nat-Gateway', 'Hub-and-Spoke-with-Nat-Gateway'."
  }
}

variable "frontdoor_sku" {
  type        = string
  description = "Specifies the SKU for Azure Front Door. Options are: 'Standard' or 'Premium'."
  default     = "Standard"

  validation {
    condition = (
      contains(["Standard", "Premium"], var.frontdoor_sku)
    )
    error_message = "The variable 'frontdoor_sku' must be one of: 'Standard' or 'Premium'."
  }
}

/*
variable "container_app_fqdn" {
  type        = string
  description = "The Azure Container App ingress FQDN that Application Gateway routes traffic to (for example: myapp.orangecliff-123456.australiaeast.azurecontainerapps.io)."
  default     = "myapp.orangecliff-123456.australiaeast.azurecontainerapps.io"
  validation {
    condition     = length(trimspace(var.container_app_fqdn)) > 0
    error_message = "container_app_fqdn must be set to a non-empty Container App ingress FQDN."
  }
  validation {
    condition     = !can(regex("^(https?://)", lower(trimspace(var.container_app_fqdn))))
    error_message = "container_app_fqdn must not start with http:// or https://."
  }
}
*/

variable "bastion_premium_private_deployment" {
  type        = bool
  description = "If true, deploys a Premium Bastion with private deployment (no public IP). If false, deploys a Premium Bastion with public deployment."
  default     = false

  ## https://learn.microsoft.com/en-us/azure/bastion/bastion-sku-comparison
  validation {
    condition = (
      var.bastion_sku != "Premium" || var.bastion_premium_private_deployment == false
    )
    error_message = "The variable 'bastion_premium_private_deployment' can only be set to true if 'bastion_sku' is Premium."
  }
}

variable "deploy_ai_embeddings" {
  type        = bool
  description = "If true, deploys AI embeddings for the environment. If false, does not deploy AI embeddings."
  default     = false
}

variable "aca_enable_dapr" {
  type        = bool
  description = "If true, enables Dapr for the Azure Container Apps environment. If false, does not enable Dapr."
  default     = false
}

variable "aca_consumption_gpu_enabled" {
  type        = bool
  description = "If true, adds a Consumption GPU workload profile to the Azure Container Apps environment."
  default     = false
}

variable "aca_consumption_gpu_profile_type" {
  type        = string
  description = "Consumption GPU workload profile type for ACA (for example: Consumption-GPU-NC8as-T4)."
  default     = "Consumption-GPU-NC8as-T4"

  validation {
    condition     = can(regex("^Consumption-GPU-[A-Za-z0-9-]+$", var.aca_consumption_gpu_profile_type))
    error_message = "aca_consumption_gpu_profile_type must start with 'Consumption-GPU-' (for example: Consumption-GPU-NC8as-T4)."
  }
}

variable "aca_consumption_gpu_min_count" {
  type        = number
  description = "Minimum replica count for the ACA Consumption GPU workload profile."
  default     = 0

  validation {
    condition     = var.aca_consumption_gpu_min_count >= 0
    error_message = "aca_consumption_gpu_min_count must be 0 or greater."
  }
}

variable "aca_consumption_gpu_max_count" {
  type        = number
  description = "Maximum replica count for the ACA Consumption GPU workload profile."
  default     = 1

  validation {
    condition     = var.aca_consumption_gpu_max_count == null || var.aca_consumption_gpu_min_count == null || var.aca_consumption_gpu_max_count >= var.aca_consumption_gpu_min_count
    error_message = "aca_consumption_gpu_max_count must be null or greater than or equal to aca_consumption_gpu_min_count (when both are set)."
  }
}

variable "custom_dns_zone_name" {
  type        = string
  description = "The purchased (and active) DNS zone name that must both exist and be active in the referenced tenant"
  default     = "webstean.com" ## "sard.webstean.com"
  validation {
    condition     = !can(regex("^(www|app)", lower(try(trimspace(var.custom_dns_zone_name), ""))))
    error_message = "dns_zone_name must not start with www or app."
  }
  validation {
    condition     = !can(regex("^(https?://)", lower(try(trimspace(var.custom_dns_zone_name), ""))))
    error_message = "dns_zone_name must not start with http:// or https://."
  }
}

variable "custom_dns_azure_tenant_auth_method" {
  type        = string
  description = "How to authenticate to the Azure tenant hosting DNS zone for Let's Encrypt DNS challenge validation."
  default     = "env"
  validation {
    condition = (
      contains(["msi", "oidc", "wli", "cli", "env", "pipeline"], lower(var.custom_dns_azure_tenant_auth_method))
    )
    ##  "oidc" - need federation setup on the Entra ID App Registration or User Assigned Identity with the correct permissions to manage the DNS zone
    ##  "env"  - need a secret defined via AZURE_CLIENT_SECRET that matches what is specified in App Registration (User Assigned Identity is not supported)
    error_message = "custom_dns_azure_tenant_auth_method must be either 'msi', 'oidc', 'wli', 'cli', 'env', or 'pipeline'."
  }
}

variable "custom_dns_azure_tenant_id" {
  type        = string
  description = "The Azure tenant ID hosting the DNS zone for Let's Encrypt DNS challenge validation."
  default     = "fd72f9ff-96b6-4a20-a870-ceaa17d70bc8"
  validation {
    condition     = try(trimspace(var.custom_dns_zone_name), "") == "" || try(trimspace(var.custom_dns_azure_tenant_id), "") != ""
    error_message = "custom_dns_azure_tenant_id cannot be empty when custom_dns_zone_name is set."
  }
}

variable "custom_dns_azure_subscription_id" {
  type        = string
  description = "The Azure subscription ID hosting the DNS zone for Let's Encrypt DNS challenge validation."
  default     = "2d2089b6-d701-49aa-9600-bc2e3796d53a"
  validation {
    condition     = try(trimspace(var.custom_dns_zone_name), "") == "" || try(trimspace(var.custom_dns_azure_subscription_id), "") != ""
    error_message = "The variable 'custom_dns_azure_subscription_id' cannot be empty when 'custom_dns_zone_name' is set."
  }
}

variable "custom_dns_azure_resource_group_name" {
  type        = string
  description = "The Azure resource group hosting the DNS zone for Let's Encrypt DNS challenge validation."
  default     = "lscph-global-dns-public-rg"
  validation {
    condition     = try(trimspace(var.custom_dns_zone_name), "") == "" || try(trimspace(var.custom_dns_azure_resource_group_name), "") != ""
    error_message = "The variable 'custom_dns_azure_resource_group_name' cannot be empty when 'custom_dns_zone_name' is set."
  }
}

variable "custom_dns_azure_client_id" {
  type        = string
  description = "The Azure client ID for the identity that has enough access to successfully perform the Let's Encrypt DNS challenge"
  default     = "c25795e5-4f48-4ef7-9a9c-12cf65d16487" ## DNS-webstean.com
  validation {
    condition     = try(trimspace(var.custom_dns_zone_name), "") == "" || try(trimspace(var.custom_dns_azure_client_id), "") != ""
    error_message = "The variable 'custom_dns_azure_client_id' cannot be empty when 'custom_dns_zone_name' is set."
  }
}

variable "custom_dns_azure_client_secret" {
  type        = string
  description = "The Azure client secret for the identity that has enough access to successfully perform the Let's Encrypt DNS challenge"
  default     = "cH58Q~xi9riJJTcWc5VlKuyFdWZNKFmabMl_tc-S" ## "supersecret"
  validation {
    condition     = try(trimspace(var.custom_dns_azure_client_secret), "") == "" || lower(var.custom_dns_azure_tenant_auth_method) == "env"
    error_message = "The variable 'custom_dns_azure_client_secret' can only be set when 'custom_dns_azure_tenant_auth_method' is 'env'."
  }
}

variable "vwan_hub_id" {
  type        = string
  description = "The ID of the Azure Virtual WAN hub to which the route table will be associated."
  default     = null ## azurerm_virtual_hub.example.id 
  validation {
    condition = (
      (try(trimspace(var.vwan_hub_id), "") == "" && try(trimspace(var.vwan_hub_firewall_id), "") == "") ||
      (try(trimspace(var.vwan_hub_id), "") != "" && try(trimspace(var.vwan_hub_firewall_id), "") != "")
    )
    error_message = "Both variables 'vwan_hub_id' and 'vwan_hub_firewall_id' must either both be set or both be empty."
  }
}

variable "vwan_hub_firewall_id" {
  type        = string
  description = "The ID of the Azure Virtual WAN hub to which the route table will be associated."
  default     = null ## azurerm_firewall.hub.id
}

variable "vmss_disk_controller_type" {
  type        = string
  description = "The disk controller type for the Virtual Machine Scale Set."
  ## Make currently be set to 'SCSI', NVMe does not support hibernation, which we need.
  default = "SCSI" ## Possible values are 'SCSI' and 'NVMe'. Defaults to 'SCSI'.
}

variable "vmss_sku_name" {
  type        = string
  description = "The Azure VM SKU to be deployed. (if not set, a random valid SKU will be selected from the list of available SKUs for the deployment region)"
  default     = "Standard_D2s_v5" ## Standard_D2s_v5
}

variable "vmss_autoscale_min_capacity" {
  description = "Minimum instance count."
  type        = number
  default     = 1
}

variable "vmss_autoscale_weekend_capacity" {
  description = "Fixed instance count to run during the weekend low-usage window."
  type        = number
  default     = 0
}

variable "vmss_autoscale_default_capacity" {
  description = "Default instance count."
  type        = number
  default     = 1
}

variable "vmss_autoscale_max_capacity" {
  description = "Maximum instance count."
  type        = number
  default     = 1
}

variable "vmss_autoscale_scale_out_cpu_threshold" {
  description = "Average CPU percentage that triggers a scale-out."
  type        = number
  default     = 70

  validation {
    condition     = var.vmss_autoscale_scale_out_cpu_threshold >= 20 && var.vmss_autoscale_scale_out_cpu_threshold <= 90
    error_message = "The variable 'vmss_autoscale_scale_out_cpu_threshold' must be between 20 and 90."
  }
}

variable "vmss_autoscale_scale_out_increase_count" {
  description = "Number of instances to add per scale-out event ('Increase count by')."
  type        = number
  default     = 1
}

variable "vmss_autoscale_time_window" {
  description = "Look-back window for the average CPU calculation (ISO 8601 duration)."
  type        = string
  default     = "PT10M"
}

variable "vmss_autoscale_time_grain" {
  description = "Granularity of metric data points collected (ISO 8601 duration)."
  type        = string
  default     = "PT1M"
}

variable "vmss_autoscale_predictive_look_ahead_time" {
  description = "How far ahead predictive autoscale forecasts demand (ISO 8601 duration)."
  type        = string
  default     = "PT5M"
}

variable "vmss_autoscale_cooldown" {
  description = "Time to wait after a scale action before scaling again (ISO 8601 duration)."
  type        = string
  default     = "PT30M"
}

variable "vmss_autoscale_business_hours_start" {
  description = "Hour (0-23) each weekday when the CPU-based business-hours profile takes over from the overnight 'zero' profile."
  type        = number
  default     = 16
}

variable "vmss_otel_counter_specifiers" {
  type        = list(string)
  description = "OTel system metrics to collect. Defaults to the standard free set."
  default = [
    "system.filesystem.usage",
    "system.disk.io",
    "system.disk.operation_time",
    "system.disk.operations",
    "system.memory.usage",
    "system.network.io",
    "system.cpu.time",
    "system.network.dropped",
    "system.network.errors",
    "system.uptime",
  ]
}

variable "pls_nat_ip_configurations" {
  type = list(object({
    name               = string
    primary            = bool
    private_ip_address = optional(string)
  }))
  description = "One or more (max 8) NAT IP configurations for the Private Link Service. Exactly one must have primary = true."
  default = [
    {
      name    = "primary"
      primary = true
    }
  ]

  validation {
    condition     = length([for c in var.pls_nat_ip_configurations : c if c.primary]) == 1
    error_message = "Exactly one pls_nat_ip_configurations entry must have primary = true."
  }
}

variable "proxy_protocol_enabled" {
  type        = bool
  description = "Whether the Private Link Service should support Proxy Protocol (to preserve source IP to the backend)."
  default     = false
}

variable "pls_allowed_fqdns" {
  type        = list(string)
  description = "FQDNs allowed for the Private Link Service."
  default     = []
}
