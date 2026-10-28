resource "azurerm_storage_account" "this" {
  name                            = "stlp${var.name_suffix}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  public_network_access           = "Disabled"
  tags                            = var.tags

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "application" {
  name                  = var.use_case_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_search_service" "this" {
  name                          = "search-${var.use_case_name}-${var.name_suffix}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = "basic"
  replica_count                 = 1
  partition_count               = 1
  local_authentication_enabled  = false
  public_network_access_enabled = false
  tags                          = var.tags
}

resource "azurerm_cosmosdb_account" "this" {
  name                          = "cosmos-${substr(var.use_case_name, 0, 30)}-${var.name_suffix}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  offer_type                    = "Standard"
  kind                          = "GlobalDocumentDB"
  local_authentication_enabled  = false
  public_network_access_enabled = false
  minimal_tls_version           = "Tls12"
  tags                          = var.tags

  capabilities {
    name = "EnableServerless"
  }
  consistency_policy {
    consistency_level = "Session"
  }
  geo_location {
    location          = var.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "application" {
  name                = var.use_case_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-${var.name_suffix}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  public_network_access_enabled = false
  tags                          = var.tags
}

locals {
  backing_endpoints = {
    blob = {
      id          = azurerm_storage_account.this.id
      subresource = "blob"
    }
    search = {
      id          = azurerm_search_service.this.id
      subresource = "searchService"
    }
    cosmos = {
      id          = azurerm_cosmosdb_account.this.id
      subresource = "Sql"
    }
    keyvault = {
      id          = azurerm_key_vault.this.id
      subresource = "vault"
    }
  }
}

module "private_endpoint" {
  source   = "../private-endpoint"
  for_each = local.backing_endpoints

  name                = "pe-${each.key}-${var.use_case_name}-${var.name_suffix}"
  resource_group_name = var.private_endpoint_resource_group_name
  location            = var.location
  tags                = var.tags
  subnet_id           = var.private_endpoint_subnet_id
  target_resource_id  = each.value.id
  subresource_name    = each.value.subresource
  dns_zone_ids        = [var.dns_zone_ids[each.key]]
}
