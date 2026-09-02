locals {
  storage_friendly_name      = "Storage Accounts"
  storage_name               = "st-${var.prefix}"
  storage_name_location      = lower("${local.storage_name}-${lower(var.location)}")
  storage_random_suffix      = substr(md5(local.storage_name_location), 0, 6)
  storage_name_hostname      = lower(substr(replace("c${local.storage_random_suffix}${local.storage_name_location}", "-", ""), 0, 24))
  diag_storage_name          = "dia-${var.prefix}"
  diag_storage_name_location = lower("${local.diag_storage_name}-${lower(var.location)}")
  diag_storage_random_suffix = substr(md5(local.diag_storage_name_location), 0, 6)
  diag_storage_name_hostname = lower(substr(replace("d${local.diag_storage_random_suffix}${local.diag_storage_name_location}", "-", ""), 0, 24))
}

resource "azurerm_storage_account" "this" {
  name                            = local.storage_name_hostname
  resource_group_name             = module.environment_resource_group.resource.name
  location                        = module.environment_resource_group.resource.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true ## still needed for compatbility, such ACA and Azure Data Box Gateway, and Azure File Sync, and Azure Backup, and Azure Site Recovery, and Azure Storage Explorer, and AzCopy, and Microsoft SQL Server, and Windows Server 2012 R2 or later, and Windows 8.1 or later, and Windows PowerShell 5.1 or later, and Windows PowerShell Core 6.0 or later, and Windows PowerShell Core 7.0 or later, and Windows PowerShell Core 7.1 or later, and Windows PowerShell Core 7.2 or later, and Windows PowerShell Core 7.3 or later, and Windows PowerShell Core 7.4 or later
  allow_nested_items_to_be_public = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true
  public_network_access_enabled   = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true

  #blob_properties {
  #  versioning_enabled = true
  #}

  network_rules {
    default_action             = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? "Deny" : "Allow"
    bypass                     = ["AzureServices"]
    ip_rules                   = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? [] : ["0.0.0.0/0"]
    virtual_network_subnet_ids = [for subnets in azurerm_virtual_network.this.subnet : subnets.id if contains(subnets.service_endpoints, "Storage")]
  }

  azure_files_authentication {
    directory_type = "AADKERB"
    #default_share_level_permission = "StorageFileDataSmbShareElevatedContributor"
  }

  ## share_properties {
  ##  smb {
  ## versions - (Optional) A set of SMB protocol versions. Possible values are SMB2.1, SMB3.0, and SMB3.1.1.
  ##versions                        = ["SMB2.1", "SMB3.0"]
  ##kerberos_ticket_encryption_type = ["AES-256"]     ## AES-256, RC4-HMAC
  ## channel_encryption_type         = ["AES-256-GCM"] ## "AES-128-CCM" "AES-128-GCM" "AES-256-GCM"
  ## authentication_types - (Optional) A set of SMB authentication methods. Possible values are NTLMv2, and Kerberos.
  ## authentication_types = ["Kerberos", "NTLMv2"] ## NTLMv2 is needed for ACA
  ## }
  ##  }

  share_properties {
    smb {
      versions                        = ["SMB2.1", "SMB3.0", "SMB3.1.1"]
      kerberos_ticket_encryption_type = ["AES-256"]            ## AES-256, RC4-HMAC
      channel_encryption_type         = ["AES-256-GCM"]        ## AES-128-CCM, AES-128-GCM, AES-256-GCM
      authentication_types            = ["Kerberos", "NTLMv2"] ## NTLMv2 is needed for ACA
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

resource "azurerm_storage_share" "global" {
  name               = "global"
  storage_account_id = azurerm_storage_account.this.id
  access_tier        = "Hot"
  quota              = 50
  enabled_protocol   = "SMB"
}

output "environment_storage_account_name" {
  description = "The name of the main storage account for this environment."
  sensitive   = false
  value       = azurerm_storage_account.this.name
}

output "environment_storage_file_connection_script_ps1" {
  description = "A PowerShell script to connect dirve Z: to the azure files created as part of this environment."
  sensitive   = false
  value = replace(<<-PS1
$connectTestResult = Test-NetConnection -ComputerName ${azurerm_storage_account.this.name}.file.core.windows.net -Port 445
if ($connectTestResult.TcpTestSucceeded) {
    Write-Output "Successfully connected to ${azurerm_storage_account.this.name}.file.core.windows.net on port 445."
    ## Remove any previously saved password
    cmd.exe /C "cmdkey /delete:`"${azurerm_storage_account.this.name}.file.core.windows.net`"" | Out-Null
    ## Mount the drive
    New-PSDrive -Name Z -PSProvider FileSystem -Root "\\${azurerm_storage_account.this.name}.file.core.windows.net\${azurerm_storage_share.global.name}" -Persist
} else {
    Write-Error -Message "Unable to reach the Azure storage account ${azurerm_storage_account.this.name}.file.core.windows.net via port 445. Check to ensure a proxy, firewall, or ISP is not blocking port 445, or use Azure P2S VPN, Azure S2S VPN, or Express Route to tunnel SMB traffic over a different port."
}
PS1
  , "\n", "\r\n")
}

resource "azurerm_role_assignment" "github_storage_owner_role" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Owner"
  principal_id         = data.azurerm_client_config.current.object_id
  description          = local.iac_message
}
## Contributor to itself for github integration
resource "azurerm_role_assignment" "umi_storage_contributor_role" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.environment.principal_id
  description          = local.iac_message
}
## https://learn.microsoft.com/en-us/azure/azure-monitor/vm/performance-diagnostics-run?tabs=windows
resource "azurerm_role_assignment" "umi_storage_table_data_reader_role" {
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Table Data Reader"
  principal_id         = azurerm_user_assigned_identity.environment.principal_id
  description          = local.iac_message
}

/*
resource "azurerm_monitor_diagnostic_setting" "storage_metrics" {
  name                       = "Metrics-${azurerm_storage_account.this.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
*/

/*
resource "azurerm_subnet_service_endpoint_storage_policy" "storage" {
  name                = "sep-storage-allowed"
  resource_group_name = module.environment_resource_group.resource.name
  location            = module.environment_resource_group.resource.location

  definition {
    name        = "allow-only-specific-storage-account"
    description = "Allow only specific storage accounts access via service endpoint"

    service_resources = [
      azurerm_storage_account.this.id
    ]
  }
}
*/
## now, you have a policy you need apply it, to the subnet

resource "azurerm_storage_account" "diag" {
  name                            = local.diag_storage_name_hostname
  resource_group_name             = module.environment_resource_group.resource.name
  location                        = module.environment_resource_group.resource.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true
  allow_nested_items_to_be_public = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true
  public_network_access_enabled   = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? false : true

  blob_properties {
    versioning_enabled = true
  }

  network_rules {
    default_action             = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? "Deny" : "Deny"
    bypass                     = ["AzureServices"]
    ip_rules                   = (tobool(var.data_pii) || tobool(var.data_phi) || tobool(var.deploy_private_endpoints)) ? [] : ["0.0.0.0/0"]
    virtual_network_subnet_ids = [for subnets in azurerm_virtual_network.this.subnet : subnets.id if contains(subnets.service_endpoints, "Storage")]
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.environment.id]
  }

  tags = { for key, value in module.environment_resource_group.resource.tags : key => value if lower(key) != "created" }
}

/*
resource "azurerm_monitor_diagnostic_setting" "storage_metrics_diag" {
  name                       = "Metrics-${azurerm_storage_account.diag.name}-to-Azure-Monitor"
  target_resource_id         = azurerm_storage_account.diag.id
  log_analytics_workspace_id = module.log_analytics_workspace.resource_id

  enabled_metric {
    category = "AllMetrics"
  }
}
*/

resource "azurerm_storage_container" "rag_documents" {
  name                  = "rag-documents"
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
/*
resource "azurerm_role_assignment" "search_blob_reader" {
  scope                = azurerm_storage_container.rag_documents.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.ai_search_principal_id
}
*/


resource "azurerm_role_assignment" "github_storage_diag_owner_role" {
  scope                = azurerm_storage_account.diag.id
  role_definition_name = "Owner"
  principal_id         = data.azurerm_client_config.current.object_id
  description          = local.iac_message
}
## Contributor to itself for github integration
resource "azurerm_role_assignment" "umi_storage_diag_contributor_role" {
  scope                = azurerm_storage_account.diag.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.environment.principal_id
  description          = local.iac_message
}
resource "azurerm_role_assignment" "umi_storage_diag_table_data_reader_role" {
  scope                = azurerm_storage_account.diag.id
  role_definition_name = "Storage Table Data Reader"
  principal_id         = azurerm_user_assigned_identity.environment.principal_id
  description          = local.iac_message
}

output "environment_diag_storage_account_name" {
  description = "The name of the main storage account for this environment."
  sensitive   = false
  value       = azurerm_storage_account.diag.name
}
