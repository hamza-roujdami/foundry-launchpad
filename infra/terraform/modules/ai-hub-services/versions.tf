terraform {
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
