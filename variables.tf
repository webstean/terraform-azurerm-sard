// +===========================================================================================================+
// NO defaults

variable "customer" {
  type        = string
  description = "The name of the customer (free-text)"
}

variable "prefix" {
  type        = string
  description = "A short name (typically 3-8 characters, lowercase) for the customer, used as a prefix for all Azure resource names to ensure global uniqueness."
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription ID in which the resources will be deployed."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", trimspace(var.subscription_id)))
    error_message = "subscription_id must be a valid GUID."
  }
}

variable "owner_email" {
  type        = string
  description = "Email address of the resource owner, used for contact and billing notifications"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", trimspace(var.owner_email)))
    error_message = "The variable 'owner_email' must be a valid email address."
  }
}

variable "owner_entra_object_id" {
  type        = string
  description = "The Entra ID object ID for the owner of this environment"

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", trimspace(var.owner_entra_object_id)))
    error_message = "The variable 'owner_entra_object_id' must be a valid GUID."
  }
}
variable "owner_entra_display_name" {
  type        = string
  description = "Display name of the owner in Entra ID for RBAC role assignment and resource access control."
}

variable "sql_administrator_group_object_id" {
  type        = string
  description = "The Entra ID object ID for the SQL administrator group (can be a user or a group)"

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", trimspace(var.sql_administrator_group_object_id)))
    error_message = "The variable 'sql_administrator_group_object_id' must be a valid GUID."
  }
}
variable "sql_administrator_group_display_name" {
  type        = string
  description = "Entra ID display name for the user or group that will have SQL Server administrator permissions."
}

// +===========================================================================================================+
// have defaults

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
  type        = string
  description = "Azure Bastion SKU tier that determines features and pricing. See https://learn.microsoft.com/en-us/azure/bastion/bastion-sku-comparison"
  default     = "Developer"

  ## https://learn.microsoft.com/en-us/azure/bastion/bastion-sku-comparison
  validation {
    condition = (
      contains(["Developer", "Basic", "Standard", "Premium"], var.bastion_sku)
    )
    error_message = "The variable 'bastion_sku' must be one of: 'Developer', 'Basic', 'Standard', 'Premium'."
  }
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
  description = "Connectivity mode for the SQL Server endpoint: 'PRIVATE' (VNet via Private Endpoint), or 'PUBLIC' (internet-facing)."
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
    error_message = "The variable 'inbound_access' must be one of: 'None', 'App-Gateway', 'FrontDoor'."
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
  description = "Consumption GPU workload profile type for Azure Container Apps (e.g., Consumption-GPU-NC8as-T4 for NVIDIA T4 GPUs)."
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
  description = "An active DNS zone name (e.g., example.com) already purchased and configured in the Azure subscription for custom domain configuration."
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
  description = "The ID of the Azure Firewall deployed in the Virtual WAN hub for filtering and routing traffic."
  default     = null ## azurerm_firewall.hub.id
}

variable "vmss_disk_controller_type" {
  type        = string
  description = "Disk controller type for the Virtual Machine Scale Set. Use 'SCSI' for hibernation support; 'NVMe' is faster but does not support hibernation."
  ## Make currently be set to 'SCSI', NVMe does not support hibernation, which we need.
  default = "SCSI" ## Possible values are 'SCSI' and 'NVMe'. Defaults to 'SCSI'.
}

variable "vmss_hibernation_enabled" {
  type        = bool
  description = "Whether hibernation is enabled for the Virtual Machine Scale Set. Requires 'vmss_disk_controller_type' to be 'SCSI'."
  default     = true

  validation {
    condition     = !var.vmss_hibernation_enabled || var.vmss_disk_controller_type == "SCSI"
    error_message = "The variable 'vmss_hibernation_enabled' can only be true if 'vmss_disk_controller_type' is set to 'SCSI'."
  }
}

variable "vmss_sku_name" {
  type        = string
  description = "Azure Virtual Machine SKU for the scale set (e.g., Standard_D2s_v5). Determines vCPU, memory, and pricing."
  default     = "Standard_D2s_v5" ## Standard_D2s_v5
}

variable "vmss_autoscale_min_capacity" {
  description = "Virtual Machine Scale Set: minimum number of instances to maintain at all times."
  type        = number
  default     = 1
}

variable "vmss_autoscale_weekend_capacity" {
  description = "Virtual Machine Scale Set: fixed instance count to run during the weekend low-usage window."
  type        = number
  default     = 0
}

variable "vmss_autoscale_default_capacity" {
  description = "Virtual Machine Scale Set: default instance count used during normal business hours."
  type        = number
  default     = 1
}

variable "vmss_autoscale_max_capacity" {
  description = "Virtual Machine Scale Set: maximum number of instances to scale up to."
  type        = number
  default     = 1
}

variable "vmss_autoscale_scale_out_cpu_threshold" {
  description = "Virtual Machine Scale Set: average CPU percentage threshold that triggers a scale-out (add instances)."
  type        = number
  default     = 70

  validation {
    condition     = var.vmss_autoscale_scale_out_cpu_threshold >= 20 && var.vmss_autoscale_scale_out_cpu_threshold <= 90
    error_message = "The variable 'vmss_autoscale_scale_out_cpu_threshold' must be between 20 and 90."
  }
}

variable "vmss_autoscale_scale_out_increase_count" {
  description = "Virtual Machine Scale Set: number of instances to add per scale-out event."
  type        = number
  default     = 1
}

variable "vmss_autoscale_time_window" {
  description = "Virtual Machine Scale Set: look-back window for the average CPU calculation in ISO 8601 format (e.g., PT10M for 10 minutes)."
  type        = string
  default     = "PT10M"
}

variable "vmss_autoscale_time_grain" {
  description = "Virtual Machine Scale Set: granularity/frequency of metric data points collected in ISO 8601 format (e.g., PT1M for 1 minute intervals)."
  type        = string
  default     = "PT1M"
}

variable "vmss_autoscale_predictive_look_ahead_time" {
  description = "Virtual Machine Scale Set: how far ahead predictive autoscale forecasts demand in ISO 8601 format (e.g., PT5M for 5 minutes ahead)."
  type        = string
  default     = "PT5M"
}

variable "vmss_autoscale_cooldown" {
  description = "Virtual Machine Scale Set: time to wait after a scale action before scaling again in ISO 8601 format (e.g., PT30M for 30 minutes)."
  type        = string
  default     = "PT30M"
}

variable "vmss_autoscale_business_hours_start" {
  description = "Virtual Machine Scale Set: hour (0-23) each weekday when the CPU-based business-hours autoscale profile activates."
  type        = number
  default     = 16 ## 4pm
}

variable "vmss_otel_counter_specifiers" {
  type        = list(string)
  description = "Virtual Machine Scale Set: OpenTelemetry system metrics to collect from instances. Defaults to the standard free metrics set."
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

variable "pls_proxy_protocol_enabled" {
  type        = bool
  description = "Whether the Private Link Service should support Proxy Protocol (to preserve source IP to the backend)."
  default     = false
}

variable "pls_allowed_fqdns" {
  type        = list(string)
  description = "FQDNs allowed for the Private Link Service."
  default     = []
}
