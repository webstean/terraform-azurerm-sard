terraform {
  required_version = ">= 1.9.0, < 2.0"

  required_providers {
    azurerm = {
      ## Azure resource manager
      source  = "hashicorp/azurerm"
      version = "~>4.0, < 5.0"
    }
    azuread = {
      ## Azure AD (Entra ID)
      source  = "hashicorp/azuread"
      version = "~>3.0, < 4.0"
    }
    msgraph = {
      ## Microsoft Graph - replacement for azuread *future*
      version = "~> 0.0, < 1.0"
      source  = "microsoft/msgraph"
    }
    azapi = {
      ## use for Azure resources that are not directly support by azurerm or azuread providers
      source  = "azure/azapi"
      version = "~>2.0, < 3.0"
    }
    random = {
      ## Random
      source  = "hashicorp/random"
      version = "~>3.0, < 4.0"
    }
  }
}

provider "azurerm" {
  ## "extended" is chosen over "automatic" to ensure all recommended and custom resource providers are registered, as required by Azure Landing Zones and advanced scenarios.
  resource_provider_registrations = "extended"
  ## These are recommendations from the Azure Landing Zone, plus some others :-)
  resource_providers_to_register = [
    "Microsoft.Advisor",
    "Microsoft.AlertsManagement",
    "Microsoft.App",
    "Microsoft.ApiCenter",
    "Microsoft.ApiManagement",
    "Microsoft.Automation",
    "Microsoft.AzureTerraform",
    "Microsoft.Cache",
    "Microsoft.Capacity",
    "Microsoft.CodeSigning",
    "Microsoft.Communication",
    "Microsoft.Compute",
    "Microsoft.Compute/EncryptionAtHost",
    "Microsoft.ContainerRegistry",
    "Microsoft.ContainerService",
    "Microsoft.DataBoxEdge",
    "Microsoft.Dashboard",
    "Microsoft.DevCenter",
    "Microsoft.DeviceUpdate",
    "Microsoft.DevOpsInfrastructure",
    "Microsoft.DevTestLab",
    "Microsoft.EdgeZones",
    "Microsoft.EventGrid",
    "Microsoft.ExtendedLocation",
    "Microsoft.GuestConfiguration",
    "Microsoft.HorizonDB",
    "Microsoft.Insights",
    "Microsoft.IoTSecurity",
    "Microsoft.IoTOperations",
    "Microsoft.KeyVault",
    "Microsoft.Monitor",
    "Microsoft.ManagedIdentity",
    "Microsoft.ManagedOps",
    "Microsoft.ManagedServices",
    "Microsoft.Management",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.OperationsManagement",
    "Microsoft.PolicyInsights",
    "Microsoft.Purview",
    "Microsoft.RecoveryServices",
    "Microsoft.ResourceHealth",
    "Microsoft.Security",
    "Microsoft.SecurityInsights",
    "Microsoft.ServiceLinker",
    "Microsoft.StandbyPool",
    "Microsoft.Storage",
    "Microsoft.Sql",
    "Microsoft.VerifiedId",
    "NGINX.NGINXPLUS",
  ]
  features {
    enhanced_validation {
      preflight_enabled = true
    }
    app_configuration {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = true
    }
    api_management {
      purge_soft_delete_on_destroy = true # Keep soft-deleted API Management resources for recovery.
      recover_soft_deleted         = true # Automatically recover soft-deleted API Management resources.
    }
    cognitive_account {
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false # Allow deletion of resource groups even if they contain resources.
    }
    key_vault {
      purge_soft_delete_on_destroy    = true # Retain soft-deleted Key Vaults for potential recovery.
      recover_soft_deleted_key_vaults = true # Automatically recover soft-deleted Key Vaults.
    }
    log_analytics_workspace {
      permanently_delete_on_destroy = true # Ensure Log Analytics Workspaces are permanently deleted on destroy.
    }
    machine_learning {
      purge_soft_deleted_workspace_on_destroy = true # Permanently delete soft-deleted ML workspaces on destroy.
    }
    virtual_machine {
      delete_os_disk_on_deletion = true # Automatically delete OS disks when deleting VMs.
    }
    template_deployment {
      delete_nested_items_during_deletion = false # Do not delete nested items during template deployment deletion.
    }
  }
  storage_use_azuread = true
  ## Authentication strategy: Prefer OIDC and Azure CLI for authentication;
  ## Managed Identity and AKS Workload Identity are disabled for explicit control and compatibility.
  use_oidc                  = true
  use_aks_workload_identity = false
  use_msi                   = false
  use_cli                   = true
}

provider "msgraph" {
  ## Authentication strategy: Prefer OIDC and Azure CLI for authentication;
  ## Managed Identity and AKS Workload Identity are disabled for explicit control and compatibility.
  use_oidc                  = true
  use_aks_workload_identity = false
  use_msi                   = false
  use_cli                   = true
}

provider "azuread" {
  ## Authentication strategy: Prefer OIDC and Azure CLI for authentication;
  ## Managed Identity and AKS Workload Identity are disabled for explicit control and compatibility.
  use_oidc                  = true
  use_aks_workload_identity = false
  use_msi                   = false
  use_cli                   = true
}

provider "azapi" {
  ## Authentication strategy: Prefer OIDC and Azure CLI for authentication;
  ## Managed Identity and AKS Workload Identity are disabled for explicit control and compatibility.
  use_oidc                  = true
  use_aks_workload_identity = false
  use_msi                   = false
  use_cli                   = true
  enable_preflight          = true
}

/*
// imports only allow in root modules
resource "azurerm_resource_provider_feature_registration" "encryption_at_host" {
  provider_name = "Microsoft.Compute"
  name          = "EncryptionAtHost"
}
import {
  to = azurerm_resource_provider_feature_registration.encryption_at_host
  id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Features/providers/Microsoft.Compute/features/EncryptionAtHost"
}
*/
