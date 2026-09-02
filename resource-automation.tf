## Automation Account, created at subscription (lgoal) level since we are not limited to 2 for the number of Automaiton account per subscription

resource "azurerm_automation_variable_string" "user_assigned_identity" {
  name                    = "USER_ASSIGNED_IDENTITY_PRINCIPAL_ID"
  resource_group_name     = module.environment_resource_group.resource.name
  automation_account_name = var.automation_account_name
  encrypted               = (tobool(var.data_pii) == true || tobool(var.data_phi) == true) ? true : false

  value       = azurerm_user_assigned_identity.environment.principal_id
  description = "User Assigned Identity"
}

resource "azurerm_automation_runbook" "demo_powershell_script1" {
  name = "Get-AzResourceGroupInfo for prefix: ${var.prefix}"

  resource_group_name      = module.environment_resource_group.resource.name
  automation_account_name  = var.automation_account_name
  location                 = module.environment_resource_group.resource.location
  runtime_environment_name = "PowerShell-7.2" ## azurerm_automation_runtime_environment.pwsh76.name

  job_schedule {
    schedule_name = "Every-Sunday-2AM"
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
  description  = "Example scheduled runbook for prefix: ${var.prefix} - maintained in Terraform"
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
            $defaultRgName = "${lower(module.environment_resource_group.resource.name)}"
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

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}
