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
  }
}
