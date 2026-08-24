locals {
  aaa_name          = "aaa-${var.prefix}"
  aaa_name_location = lower("${local.aaa_name}-${lower(var.location)}")
  aaa_random_suffix = substr(md5(local.aaa_name_location), 0, 6)
  aaa_name_hostname = lower(substr(replace("l${local.aaa_random_suffix}${local.aaa_name_location}", "-", ""), 0, 24))
  ## local variables for schedule timings
  ## Check out!!
  ## https://bgelens.nl/terraform-automation-resources/
  ##  current_time            = timestamp()
  ##  start_wallclock_time    = "01.55"
  ##  current_wallclock_time  = formatdate("h.mm", local.current_time)
  ##  schedule_tomorrow       = (local.current_wallclock_time >= local.start_wallclock_time)
  ### today                   = formatdate("YYYY-MM-DD", local.current_time)
  tomorrow    = formatdate("YYYY-MM-DD", timeadd(timestamp(), "48h"))
  now         = formatdate("YYYY-MM-DD", timestamp())
  start_time  = formatdate("YYYY-MM-DD", timeadd(timestamp(), "-1m"))
  expiry_time = "9999-12-31T23:59:59+10:00"
}

## Automation Account for each region - which are free of charge
## more than 5x Hybrid Workers costs money
## certain number of job run times (currently 500 minutes) and watcher per month (currently 744 hours)
resource "azurerm_automation_account" "this" {
  name                = local.aaa_name_location
  resource_group_name = module.environment_resource_group.resource.name
  location            = azurerm_resource_group.environment.location

  local_authentication_enabled  = false
  public_network_access_enabled = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }
  sku_name = "Basic"

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

resource "azurerm_automation_runtime_environment" "pwsh76" {
  name                  = "PowerShell-7.6-custom"
  automation_account_id = azurerm_automation_account.this.id
  location              = azurerm_resource_group.environment.location
  description           = "PowerShell 7.6 runtime environment"
  runtime_language      = "PowerShell"
  runtime_version       = "7.6"
  runtime_default_packages = {
    "Az"        = "15.4.0"
    "Azure CLI" = "2.77.0"
  }
}

/*
resource "azurerm_role_assignment" "automation_reader" {
  scope                = azurerm_resource_group.environment.id
  role_definition_name = "Reader"
  principal_id         = azurerm_automation_account.this.identity[0].principal_id
  depends_on           = [azurerm_automation_account.this]
}
*/

/*
resource "azurerm_monitor_diagnostic_setting" "aaa1" {
  name                       = "Logs-and-Audit-${azurerm_automation_account.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_automation_account.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_log {
    category_group = "audit"
  }
  enabled_log {
    category_group = "allLogs"
  }
}

resource "azurerm_monitor_diagnostic_setting" "aaa2" {
  name                       = "Metrics-${azurerm_automation_account.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_automation_account.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
*/

/*
resource "azurerm_automation_connection" "automation-sp1" {
  name                    = "automation-contributor-sp"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  type                    = "AzureServicePrincipal"
  description             = azuread_application.automation.description

  values = {
    "ApplicationId" : data.azurerm_client_config.current.client_id
    "TenantId" : data.azurerm_client_config.current.tenant_id,
    "SubscriptionId" : data.azurerm_client_config.current.subscription_id,
    "CertificateThumbprint" : azurerm_key_vault_certificate.self-cert[var.default_region].thumbprint
  }
}
*/

// Azure AD: Built in roles: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles

/*
// Hybrid Runbook Worker Group
resource "azurerm_automation_hybrid_runbook_worker_group" "linux" {
  for_each = azurerm_storage_account.automation

  name                    = "Default-Linux-Runbook-Workers"
  resource_group_name     = azurerm_resource_group.automation[each.key].name
  automation_account_name = azurerm_automation_account.automation[each.key].name
  // credential_name = azurerm_automation_credential
}

resource "azurerm_automation_hybrid_runbook_worker_group" "windows" {
  for_each = azurerm_storage_account.automation

  name                    = "Default-Windows-Runbook-Workers"
  resource_group_name     = azurerm_resource_group.automation[each.key].name
  automation_account_name = azurerm_automation_account.automation[each.key].name
  // credential_name = azurerm_automation_credential
}
*/

/*
resource "azurerm_automation_hybrid_runbook_worker" "worker1" {
  resource_group_name     = 
  automation_account_name = 
  worker_group_name       = azurerm_automation_hybrid_runbook_worker_group.worker_group.name
  vm_resource_id          = azurerm_linux_virtual_machine.example.id
  worker_id               = uuid() ## "00000000-0000-0000-0000-000000000000" #unique uuid
}
*/


resource "azurerm_automation_credential" "vcenter-create" {

  name                    = "VCENTER-CREDENTIAL"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  username    = "example_user"
  password    = "example_pwd"
  description = "This is a vCenter credential for managing VMware Virtual Machines"
}

resource "azurerm_automation_variable_string" "resource-group-id" {
  name                    = "RESOURCE_GROUP_ID"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (var.data_pii == "yes" || var.data_phi == "yes") ? true : false

  value       = azurerm_resource_group.environment.id
  description = "Resource Group ID for this environment"
}
resource "azurerm_automation_variable_string" "resource-group-name" {
  name                    = "RESOURCE_GROUP_NAME"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (var.data_pii == "yes" || var.data_phi == "yes") ? true : false

  value       = module.environment_resource_group.resource.name
  description = "Resource Group Name for this environment"
}
resource "azurerm_automation_variable_string" "subscription-id" {
  name                    = "AZURE_SUBSCRIPTION_ID"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (var.data_pii == "yes" || var.data_phi == "yes") ? true : false

  value       = data.azurerm_client_config.current.subscription_id
  description = "Microsoft Azure Subscription ID"
}
resource "azurerm_automation_variable_string" "azure_tenant" {
  name                    = "AZURE_TENANT_ID"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (var.data_pii == "yes" || var.data_phi == "yes") ? true : false
  value                   = data.azurerm_client_config.current.tenant_id
  description             = "Microsoft Azure Tenant ID"
}
resource "azurerm_automation_variable_string" "power_tenant" {
  name                    = "POWER_PLATFORM_TENANT_ID"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (var.data_pii == "yes" || var.data_phi == "yes") ? true : false
  value                   = data.azurerm_client_config.current.tenant_id
  description             = "Microsoft Azure Tenant ID"
}
resource "azurerm_automation_variable_string" "fabric_tenant" {
  name                    = "FABRIC_TENANT_ID"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (var.data_pii == "yes" || var.data_phi == "yes") ? true : false
  value                   = data.azurerm_client_config.current.tenant_id
  description             = "Microsoft Fabric - Tenant ID"
}
/*
resource "azurerm_automation_variable_string" "fabric_capacity" {
  for_each = azurerm_automation_account.automation

  name                    = "FABRIC_CAPACITY"
  resource_group_name     = each.value.resource_group_name
  automation_account_name = each.value.name
  encrypted               = (var.data_pii == "yes" || var.data_phi == "yes") ? true : false
  value                   = upper(local.fabric_capacity_name)
  description             = "Microsoft Fabric - Capacity SKU"
}
*/
resource "azurerm_automation_variable_string" "app" {
  name                    = "ENVIRONMENT_NAME"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (tobool(var.data_pii) == true || tobool(var.data_phi) == true) ? true : false

  value       = var.prefix
  description = "Environment Prefix"
}

resource "azurerm_automation_variable_string" "customer" {
  name                    = "CUSTOMER_NAME"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (tobool(var.data_pii) == true || tobool(var.data_phi) == true) ? true : false

  value       = var.customer
  description = "Customer Name"
}

resource "azurerm_automation_variable_string" "admin_dns_0" {
  name                    = "USERDNSDOMAIN"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (tobool(var.data_pii) == true || tobool(var.data_phi) == true) ? true : false

  value       = "data.local"
  description = "Full DNS Domain Name of the Entra Domain Services deployed in the global/core resource landing zone"
}

resource "azurerm_automation_variable_string" "admin_dssc_domain" {
  name                    = "USERDOMAIN"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (tobool(var.data_pii) == true || tobool(var.data_phi) == true) ? true : false

  value       = "abc12"
  description = "Active Directory Domain"
}

resource "azurerm_automation_variable_string" "user_assigned_identity" {
  name                    = "USER_ASSIGNED_IDENTITY_PRINCIPAL_ID"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (tobool(var.data_pii) == true || tobool(var.data_phi) == true) ? true : false

  value       = azurerm_user_assigned_identity.environment.principal_id
  description = "User Assigned Identity"
}

resource "azurerm_automation_variable_bool" "data_pii" {
  name                    = "CONTAINS_PERSONAL_IDENTIFIABLE_INFORMATION"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (tobool(var.data_pii) == true || tobool(var.data_phi) == true) ? true : false

  value       = var.data_pii
  description = "Personal Identifiable Information"
}

resource "azurerm_automation_variable_bool" "data_phi" {
  name                    = "CONTAINS_PROTECTED_HEALTH_INFORMATION"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (tobool(var.data_pii) == true || tobool(var.data_phi) == true) ? true : false

  value       = var.data_phi
  description = "Protected Health Information"
}

/*
// Demo Runbooks
data "local_file" "demo_ps1" {
  filename = "../runbooks/powershell/demo.ps1"
}

resource "azurerm_automation_runbook" "demo_rb1" {
  name                    = "Example-Terraform-Runbook1-${local.regions[each.key].short_name}"
  location                = each.value.location
  resource_group_name     = 
  automation_account_name = 
  log_verbose             = "true"
  log_progress            = "true"
  description             = "Example runbook -  maintained in Terraform"
  runbook_type            = "PowerShell"
  content                 = data.local_file.demo_ps1.content
  tags                    = local.temporary_tags
}
*/

resource "azurerm_automation_runbook" "demo_rb2" {
  name = "Get-AzureVMTutorial"

  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name
  location                = azurerm_automation_account.this.location

  log_verbose  = "true"
  log_progress = "true"
  description  = "Example runbook -  maintained in Terraform"
  runbook_type = "PowerShellWorkflow"

  publish_content_link {
    uri = "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/c4935ffb69246a6058eb24f54640f53f69d3ac9f/101-automation-runbook-getvms/Runbooks/Get-AzureVMTutorial.ps1"
  }

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}

/*
resource "azurerm_automation_webhook" "main1" {
  name                    = "${each.value.name}-webhook"
  resource_group_name     = module.environment_resource_group.resource.name
  location                = azurerm_automation_account.this.location
  automation_account_name = azurerm_automation_account.this.name
  enabled                 = true
  expiry_time             = timeadd(timestamp(), "768h") ## 32 days
  runbook_name            = each.value.name
  parameters = {
    input = "parameter"
  }
}
*/

/*
resource "azurerm_automation_certificate" "certificate1" {
  name        = "${var.project_name}${local.regions[each.key].short_name}cert01"
  description = "This is an example certificate"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  tls_private_key.rsa[each.key].private_key_pem_pkcs8
  base64      = filebase64("certificate.pfx")
  exportable  = true
}
*/

/*
resource "azurerm_automation_source_control" "github" {
  name = "${var.project_name}${local.regions[each.key].short_name}github"
  automation_account_id = azurerm_automation_account.this.id

  folder_path = "runbooks"

  security {
    token      = var.git_automation_pat
    token_type = "PersonalAccessToken"
  }
  repository_url = var.git_automation_repo

  source_control_type     = var.git_automation_type
  branch                  = "main"
  automatic_sync          = true
  publish_runbook_enabled = true
  description             = local.iac_message
}
*/

/*
resource "azurerm_automation_watcher" "watcher" {
  name                  = "${var.project_name}${local.regions[each.key].short_name}watcher"
  automation_account_id = azurerm_automation_account.this.id
  location              = azurerm_automation_account.this.location

  script_name                    = azurerm_automation_runbook.example[each.key].name
  script_run_on                  = azurerm_automation_hybrid_runbook_worker_group.example.name
  description                    = "${var.project_name}${local.regions[each.key].short_name}watcher description"
  execution_frequency_in_seconds = 42

  script_parameters = {
    foo = "bar"
  }

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
}
*/

resource "azurerm_automation_module" "packagemanagement" {
  name                    = "PackageManagement"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/PackageManagement/"
  }
}

resource "azurerm_automation_module" "powershellget" {

  name                    = "PowerShellGet"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/PowerShellGet/"
  }
  depends_on = [
    azurerm_automation_module.packagemanagement
  ]
}

resource "azurerm_automation_module" "vmware_powercli" {
  name                    = "VMware.PowerCLI"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/VMware.PowerCLI/"
  }
}

resource "azurerm_automation_module" "pswindowsupdate" {
  name                    = "PSWindowsUpdate"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/PSWindowsUpdate/"
  }
}

resource "azurerm_automation_module" "sharepoint" {
  name                    = "Microsoft.Online.SharePoint.PowerShell"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Microsoft.Online.SharePoint.PowerShell/"
  }
}

resource "azurerm_automation_module" "pnp_powershell" {
  name                    = "PnP.PowerShell"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/PnP.PowerShell/"
  }
}

/*
resource "azurerm_automation_runtime_environment_package" "az_module" {
  name                              = "Az"
  automation_runtime_environment_id = azurerm_automation_runtime_environment.pwsh76.id

  content_uri = "https://www.powershellgallery.com/api/v2/package/Az.Accounts"
}
*/

resource "azurerm_automation_runtime_environment_package" "pswindowsupdate" {
  name                              = "PSWindowsUpdate"
  automation_runtime_environment_id = azurerm_automation_runtime_environment.pwsh76.id

  content_uri = "https://www.powershellgallery.com/api/v2/package/PSWindowsUpdate"
}

resource "azurerm_automation_runtime_environment_package" "msgraph" {
  name                              = "Microsoft.Graph"
  automation_runtime_environment_id = azurerm_automation_runtime_environment.pwsh76.id

  content_uri = "https://www.powershellgallery.com/api/v2/package/Microsoft.Graph"
}

resource "azurerm_automation_runtime_environment_package" "vmware_powercli" {
  name                              = "VMware.PowerCLI"
  automation_runtime_environment_id = azurerm_automation_runtime_environment.pwsh76.id

  content_uri = "https://www.powershellgallery.com/api/v2/package/VMware.PowerCLI"
}


resource "azurerm_automation_schedule" "sunday" {
  name                    = "Every-Sunday-2AM"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  frequency = "Week"
  interval  = 1
  timezone  = local.regions[var.location].time_zone_auto
  // start_time  = local.start_time
  expiry_time = local.expiry_time
  description = "Run every Sunday at 2am"
  week_days   = ["Sunday"]
  lifecycle {
    ignore_changes = [expiry_time]
  }
}

resource "azurerm_automation_schedule" "monday" {
  name                    = "Every-Monday-2AM"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  frequency = "Week"
  interval  = 1
  timezone  = local.regions[var.location].time_zone_auto
  // start_time  = local.start_time
  expiry_time = local.expiry_time
  description = "Run every Monday at 2am"
  week_days   = ["Monday"]
  lifecycle {
    ignore_changes = [expiry_time]
  }
}

resource "azurerm_automation_schedule" "tuesday" {

  name                    = "Every-Tuesday-2AM"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  frequency = "Week"
  interval  = 1
  timezone  = local.regions[var.location].time_zone_auto
  // start_time  = local.start_time
  expiry_time = local.expiry_time
  description = "Run every Tuesday at 2am"
  week_days   = ["Tuesday"]
  lifecycle {
    ignore_changes = [expiry_time]
  }
}

resource "azurerm_automation_schedule" "wednesday" {
  name                    = "Every-Wednesday-2AM"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  frequency = "Week"
  interval  = 1
  timezone  = local.regions[var.location].time_zone_auto
  // start_time              = local.start_time
  expiry_time = local.expiry_time
  description = "Run every Wednesday at 2am"
  week_days   = ["Wednesday"]
  lifecycle {
    ignore_changes = [expiry_time]
  }
}

resource "azurerm_automation_schedule" "thursday" {
  name                    = "Every-Thursday-2AM"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  frequency = "Week"
  interval  = 1
  timezone  = local.regions[var.location].time_zone_auto
  ## start_time  = local.start_time
  expiry_time = local.expiry_time
  description = "Run every Thursday at 2am"
  week_days   = ["Thursday"]
  lifecycle {
    ignore_changes = [expiry_time]
  }
}

resource "azurerm_automation_schedule" "friday" {
  name                    = "Every-Friday-2AM"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  frequency = "Week"
  interval  = 1
  timezone  = local.regions[var.location].time_zone_auto
  ## start_time  = local.start_time
  expiry_time = local.expiry_time
  description = "Run every Friday at 2am"
  week_days   = ["Friday"]
  lifecycle {
    ignore_changes = [expiry_time]
  }
}

resource "azurerm_automation_schedule" "saturday" {
  name                    = "Every-Saturday-2AM"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  frequency = "Week"
  interval  = 1
  timezone  = local.regions[var.location].time_zone_auto
  ## start_time  = local.start_time
  expiry_time = local.expiry_time
  description = "Run every Saturday at 2am"
  week_days   = ["Saturday"]
  lifecycle {
    ignore_changes = [expiry_time]
  }
}

resource "azurerm_automation_schedule" "monthly" {
  name                    = "Every-Month-Last-Friday-2AM"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = azurerm_automation_account.this.name

  frequency = "Month"
  ## interval  = 1
  timezone = local.regions[var.location].time_zone_auto
  ## start_time  = local.start_time
  expiry_time = local.expiry_time
  description = "Run on the last week of each month on a Friday"

  monthly_occurrence {
    day        = "Friday"
    occurrence = "-1"
  }

  lifecycle {
    ignore_changes = [expiry_time]
  }
}

resource "azurerm_automation_runbook" "demo_powershell_script1" {
  name = "Get-ResourceGroupInfo"

  resource_group_name      = module.environment_resource_group.resource.name
  automation_account_name  = azurerm_automation_account.this.name
  location                 = azurerm_automation_account.this.location
  runtime_environment_name = "PowerShell-7.2" ## azurerm_automation_runtime_environment.pwsh76.name

  job_schedule {
    schedule_name = azurerm_automation_schedule.sunday.name
    # Note: The parameter keys/names must strictly be in lowercase, even if this is not the case
    # in the runbook.
    # This is due to a limitation in Azure Automation where the parameter names are normalized.
    #The values specified don't have this limitation.

    #    parameters = {
    #      lower(resourcegroupname) = "${module.environment_resource_group.resource.name}"
    #    }
  }

  log_verbose  = "true"
  log_progress = "true"
  description  = "Example scheduled runbook -  maintained in Terraform"
  runbook_type = "PowerShell"

  content = <<-EOF
function Test-InAzureAutomation {
    <#
    .SYNOPSIS
        Detects whether the current PowerShell process is running as an Azure Automation job.

    .DESCRIPTION
        Checks $env:AZUREPS_HOST_ENVIRONMENT, which Azure Automation sets to "AzureAutomation"
        for jobs on the Azure sandbox and "AzureAutomation/" for jobs on a Hybrid Runbook Worker.
        Works across PowerShell 5.1 and 7.x runtime environments. This is the same variable
        used internally to distinguish sandbox vs. HRW execution.

    .OUTPUTS
        [PSCustomObject] with IsAutomation, IsHybridWorker, and JobId.

    .EXAMPLE
        if ((Test-InAzureAutomation).IsAutomation) { Write-Host "Running as an Automation job" }
    #>
    [CmdletBinding()]
    param()

    $hostEnv = $env:AZUREPS_HOST_ENVIRONMENT
    $isAutomation = $hostEnv -like 'AzureAutomation*'
    $isHybridWorker = $hostEnv -eq 'AzureAutomation/'

    $jobId = $null
    if ($isAutomation) {
        if ($PSVersionTable.PSVersion.Major -eq 5) {
            $jobId = $PSPrivateMetadata.JobId.Guid
        }
        elseif ($isHybridWorker) {
            $jobId = $env:PSPrivateMetadata
        }
        else {
            $jobId = $PSPrivateMetadata.JobId
        }
    }

    [PSCustomObject]@{
        IsAutomation   = [bool]$isAutomation
        IsHybridWorker = [bool]$isHybridWorker
        HostEnvironment = $hostEnv
        JobId          = $jobId
    }
}
Test-InAzureAutomation | Format-List

function Get-AzResourceGroupInfo {
    <#
    .SYNOPSIS
        Gathers basic information about an Azure resource group.
    .DESCRIPTION
        Returns resource group metadata, tag inventory, resource count by type,
        role assignment count, and any resource locks. Assumes an active
        Az.Accounts context (Connect-AzAccount already run).
    .PARAMETER ResourceGroupName
        Name of the resource group to inspect.
    .PARAMETER IncludeRoleAssignments
        Also enumerate role assignments scoped to the resource group.
        Off by default since Get-AzRoleAssignment is slow on large RGs.
    .EXAMPLE
        Get-AzResourceGroupInfo -ResourceGroupName 'rg-prod-eastus'
    .EXAMPLE
        'rg-dev-eastus2','rg-prod-eastus' | Get-AzResourceGroupInfo -IncludeRoleAssignments
    #>
    [CmdletBinding()]
    param(
      [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
      [string[]]$ResourceGroupName = @(),
        [switch]$IncludeRoleAssignments
    )

    begin {
        Write-Output "Gathering information..."

        if (-not (Get-AzContext)) {
            ## Get the user-assigned identity principal ID from Automation Variable
            $principalIdVarName = "${lower(azurerm_automation_variable_string.user_assigned_identity.name)}"
            $principalId = Get-AutomationVariable -Name $principalIdVarName -ErrorAction SilentlyContinue
            
            if ([string]::IsNullOrWhiteSpace($principalId)) {
                throw "Automation Variable '$principalIdVarName' not found or empty. Please set the user-assigned identity principal ID."
            }
            
            ## Authenticate using the user-assigned identity
            Connect-AzAccount -Identity -AccountId $principalId | Out-Null
            if (-not (Get-AzContext)) {
                throw "Connect-AzAccount -Identity failed for principal ID: '$principalId'. Confirm the managed identity is properly configured."
            }
        }

        if (-not $PSBoundParameters.ContainsKey('ResourceGroupName') -or -not $ResourceGroupName -or $ResourceGroupName.Count -eq 0) {
          $autoVarName = "resource-group-name"
          $defaultRgName = Get-AutomationVariable -Name $autoVarName -ErrorAction SilentlyContinue

          if ([string]::IsNullOrWhiteSpace($defaultRgName)) {
            $defaultRgName = "${lower(azurerm_automation_account.this.resource_group_name)}"
          }

          $ResourceGroupName = @($defaultRgName)
        }
        Write-Output "Resource group(s) to inspect: $($ResourceGroupName -join ', ')"
    }
    process {
        foreach ($rgName in $ResourceGroupName) {

            $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
            if (-not $rg) {
                Write-Warning "Resource group '$rgName' not found in current subscription context."
                continue
            }

            $resources = Get-AzResource -ResourceGroupName $rgName

            $resourceTypeCounts = $resources |
                Group-Object -Property ResourceType |
                Sort-Object -Property Count -Descending |
                ForEach-Object { [PSCustomObject]@{ ResourceType = $_.Name; Count = $_.Count } }

            $locks = Get-AzResourceLock -ResourceGroupName $rgName -ErrorAction SilentlyContinue

            $roleAssignmentCount = $null
            if ($IncludeRoleAssignments) {
                $roleAssignmentCount = (Get-AzRoleAssignment -ResourceGroupName $rgName).Count
            }

            $result = [PSCustomObject]@{
                Name                = $rg.ResourceGroupName
                Location            = $rg.Location
                SubscriptionId      = (Get-AzContext).Subscription.Id
                ProvisioningState   = $rg.ProvisioningState
                Tags                = $rg.Tags
                ResourceCount       = $resources.Count
                ResourceTypeCounts  = $resourceTypeCounts
                LockCount           = ($locks | Measure-Object).Count
                Locks               = $locks | Select-Object Name, Properties
                RoleAssignmentCount = $roleAssignmentCount
            }
            $result
      }
    }
    
}

# Runbook entry point: called with zero arguments. Azure Automation only
# exposes a "PowerShell" runbook's parameters if a param() block sits at the
# top level of the .ps1 file, outside any function. The param() above is
# scoped to Get-AzResourceGroupInfo, not this file's top level, so the
# Automation runbook itself is parameterless regardless of how the function
# is invoked here. With no args, ResourceGroupName falls back to the
# RESOURCE_GROUP_NAME Automation Variable inside the begin block.
Get-AzResourceGroupInfo | Format-List
EOF

  tags = { for key, value in azurerm_resource_group.environment.tags : key => value if lower(key) != "created" }
  depends_on = [
    azurerm_automation_runtime_environment.pwsh76,
  ]
}

