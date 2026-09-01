locals {
  environment_name          = "env-${var.prefix}"
  environment_name_location = lower("${local.environment_name}-${lower(var.location)}")
  environment_random_suffix = substr(md5(local.environment_name_location), 0, 6)
  environment_name_hostname = lower(substr(replace("c${local.environment_random_suffix}${local.environment_name_location}", "-", ""), 0, 24))
  environment_home_page     = "www.webstean.com"
  portal_link               = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/rg-${local.environment_name_location}/overview"
}

module "environment_resource_group" {
  source           = "Azure/avm-res-resources-resourcegroup/azurerm"
  version          = "~>0.0, < 1.0"
  enable_telemetry = var.enable_telemetry

  name     = "rg-${lower(local.environment_name_location)}"
  location = var.location
  role_assignments = {
    ## ==========================================================================================
    "sp_roleassignment1" = {
      role_definition_id_or_name       = "Contributor"
      principal_id                     = azurerm_user_assigned_identity.environment.principal_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment2" = {
      role_definition_id_or_name       = "User Access Administrator"
      principal_id                     = azurerm_user_assigned_identity.environment.principal_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment3" = {
      role_definition_id_or_name       = "Key Vault Administrator"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment4" = {
      role_definition_id_or_name       = "Storage Blob Data Owner"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment5" = {
      role_definition_id_or_name       = "Storage Queue Data Contributor"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment6" = {
      role_definition_id_or_name       = "Storage Table Data Contributor"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment7" = {
      role_definition_id_or_name       = "Storage File Data Privileged Contributor"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    "sp_roleassignment8" = {
      role_definition_id_or_name       = "App Configuration Data Owner"
      principal_id                     = data.azurerm_client_config.current.object_id
      skip_service_principal_aad_check = true
      principal_type                   = "ServicePrincipal"
      description                      = local.iac_message
    }
    ## ==========================================================================================
    "up_roleassignment1" = {
      role_definition_id_or_name       = "Contributor"
      principal_id                     = var.owner_entra_object_id
      skip_service_principal_aad_check = true
      principal_type                   = "User"
      description                      = local.iac_message
    }
    "up_roleassignment2" = {
      role_definition_id_or_name       = "Reader and Data Access" ## Storage Only
      principal_id                     = var.owner_entra_object_id
      skip_service_principal_aad_check = false
      principal_type                   = "User"
      description                      = local.iac_message
    }
    "up_roleassignment3" = {
      role_definition_id_or_name       = "Reader"
      principal_id                     = var.owner_entra_object_id
      skip_service_principal_aad_check = false
      principal_type                   = "User"
      description                      = local.iac_message
    }
    "up_roleassignment4" = {
      role_definition_id_or_name       = "Storage Blob Data Reader"
      principal_id                     = var.owner_entra_object_id
      skip_service_principal_aad_check = false
      principal_type                   = "User"
      description                      = local.iac_message
      # ABAC condition version 2.0 is required for blob index tag conditions
      condition_version = "2.0"

      condition = <<-CONDITION
    (
      (
        !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'})
      )
      OR
      (
        @Resource[Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags:createdby<$key_case_sensitive$>] StringEquals 'Terraform'
      )
    )
  CONDITION
    },
  }
  lock = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? {
    kind = "CanNotDelete"
  } : null
  tags = merge(local.temporary_tags, {
    type = "permanent"
  })
}

/*
resource "azurerm_resource_group" "environment" {
  name     = "rg-${local.environment_name_location}"
  location = var.location
  tags     = local.temporary_tags
  lifecycle {
    ignore_changes = [tags.created]
  }
}
*/

# Wait 10 seconds for the network watcher to be created as a byproduct of the VNet creation
resource "time_sleep" "wait_10_seconds_for_network_watcher_creation" {
  create_duration = "10s"

  depends_on = [azurerm_virtual_network.this]
}

# Network Watcher — one per region per subscription is the norm; Azure will reject a
# duplicate if one already exists in this region, so remove/import this resource if so.
data "azurerm_network_watcher" "this" {
  name                = "NetworkWatcher_${lower(var.location)}"
  resource_group_name = "NetworkWatcherRG"
  depends_on          = [azurerm_virtual_network.this]
}

output "environment_resource_group" {
  description = "The Azure Resource Group that contains this environment"
  sensitive   = false
  value       = module.environment_resource_group.resource.name
}

resource "azurerm_user_assigned_identity" "environment" {
  name = "id-${local.environment_name_location}"

  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location
  isolation_scope     = "Regional"
  tags                = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}
resource "time_sleep" "environment_identity_create_wait" {
  create_duration = "1m"
  depends_on      = [azurerm_user_assigned_identity.environment]
}
## https://learn.microsoft.com/en-us/azure/operations/configuration-enrollment#managed-identity

/*
resource "azurerm_automation_variable_string" "user_assigned_identity" {
  name                    = "USER_ASSIGNED_IDENTITY_PRINCIPAL_ID"
  resource_group_name     = azurerm_resource_group.global.name
  automation_account_name = azurerm_automation_account.this.name
  encrypted               = (tobool(var.data_pii) == true || tobool(var.data_phi) == true) ? true : false

  value       = azurerm_user_assigned_identity.environment.principal_id
  description = "User Assigned Identity"
}

resource "azurerm_automation_runbook" "demo_powershell_script1" {
  name = "Get-ResourceGroupInfo"

  resource_group_name      = azurerm_resource_group.global.name
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
    #      lower(resourcegroupname) = "${azurerm_resource_group.global.name}"
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

  tags = { for key, value in azurerm_resource_group.global.tags : key => value if lower(key) != "created" }
  depends_on = [
    azurerm_automation_runtime_environment.pwsh76,
  ]
}

*/

output "subscription_display_name" {
  description = "The subscription display name of the current Azure subscription."
  sensitive   = false
  value       = data.azurerm_subscription.current.display_name
}

output "subscription_id" {
  description = "The subscription ID of the current Azure subscription."
  sensitive   = false
  value       = data.azurerm_subscription.current.subscription_id
}

