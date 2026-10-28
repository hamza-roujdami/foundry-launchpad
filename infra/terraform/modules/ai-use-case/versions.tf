terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.11"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.13"
    }
  }
}
