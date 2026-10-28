provider "azurerm" {
  subscription_id                 = var.ai_hub_subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    cognitive_account {
      purge_soft_delete_on_destroy = false
    }
    key_vault {
      purge_soft_delete_on_destroy = false
    }
    api_management {
      purge_soft_delete_on_destroy = false
    }
  }
}

provider "azurerm" {
  alias                           = "ai_spokes"
  subscription_id                 = var.ai_spokes_subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    cognitive_account {
      purge_soft_delete_on_destroy = false
    }
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

provider "azapi" {
  subscription_id = var.ai_hub_subscription_id
  tenant_id       = var.tenant_id
}

provider "azapi" {
  alias           = "ai_spokes"
  subscription_id = var.ai_spokes_subscription_id
  tenant_id       = var.tenant_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}
