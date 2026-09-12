terraform {
  required_version = "~>1.9, < 2.0"

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
      ## Microsoft Graph - eventual replacement for azuread
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
    acme = {
      ## ACME for Let's Encrypt
      source  = "vancluever/acme"
      version = "~>2.0, < 3.0"
    }
  }
}

## assume OIDC
provider "azurerm" {
  alias = "dns"
  features {}
  tenant_id           = var.custom_dns_azure_tenant_id
  subscription_id     = var.custom_dns_azure_subscription_id
  client_id           = var.custom_dns_azure_client_id
  client_secret       = var.custom_dns_azure_tenant_auth_method == "env" ? var.custom_dns_azure_client_secret : null
  storage_use_azuread = true
  ## Authentication strategy: Prefer OIDC and Azure CLI for authentication;
  ## Managed Identity and AKS Workload Identity are disabled for explicit control and compatibility.
  use_oidc                  = var.custom_dns_azure_tenant_auth_method == "oidc" ? true : false
  use_aks_workload_identity = var.custom_dns_azure_tenant_auth_method == "wli" ? true : false
  use_msi                   = var.custom_dns_azure_tenant_auth_method == "msi" ? true : false
  use_cli                   = var.custom_dns_azure_tenant_auth_method == "cli" ? true : false
}
