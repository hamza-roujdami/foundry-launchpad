module "monitoring" {
  source = "../monitoring"

  name                = "${var.use_case_name}-${var.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  private_networking  = true
}

resource "azurerm_user_assigned_identity" "runtime" {
  name                = "id-${var.use_case_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_container_app_environment" "this" {
  name                           = "cae-${var.use_case_name}-${var.name_suffix}"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  log_analytics_workspace_id     = module.monitoring.log_analytics_workspace_id
  logs_destination               = "log-analytics"
  infrastructure_subnet_id       = var.aca_subnet_id
  internal_load_balancer_enabled = true
  public_network_access          = "Disabled"
  tags                           = var.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_private_dns_zone" "environment" {
  name                = azurerm_container_app_environment.this.default_domain
  resource_group_name = var.private_endpoint_resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "environment" {
  name                = "aca-${var.use_case_name}-${var.name_suffix}"
  private_dns_zone_id = azurerm_private_dns_zone.environment.id
  virtual_network_id  = split("/subnets/", var.aca_subnet_id)[0]
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "environment" {
  for_each = toset(["@", "*"])

  name                = each.key
  private_dns_zone_id = azurerm_private_dns_zone.environment.id
  ttl                 = 300
  records             = [azurerm_container_app_environment.this.static_ip_address]
}

locals {
  runtime_roles = {
    registry = {
      scope = var.registry.id
      role  = "AcrPull"
    }
    project = {
      scope = var.foundry.project_id
      role  = "Foundry User"
    }
    vault = {
      scope = azurerm_key_vault.this.id
      role  = "Key Vault Secrets User"
    }
    blob = {
      scope = "${azurerm_storage_account.this.id}/blobServices/default/containers/${azurerm_storage_container.application.name}"
      role  = "Storage Blob Data Contributor"
    }
    search = {
      scope = azurerm_search_service.this.id
      role  = "Search Index Data Contributor"
    }
  }
}

resource "azurerm_role_assignment" "runtime" {
  for_each = local.runtime_roles

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.runtime.principal_id
}

resource "azurerm_cosmosdb_sql_role_assignment" "runtime" {
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
  role_definition_id  = "${azurerm_cosmosdb_account.this.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_user_assigned_identity.runtime.principal_id
  scope               = "${azurerm_cosmosdb_account.this.id}/dbs/${azurerm_cosmosdb_sql_database.application.name}"
}

resource "azurerm_role_assignment" "engineer" {
  for_each = var.engineer_group_ids

  scope                = var.foundry.project_id
  role_definition_name = "Foundry User"
  principal_id         = each.value
}

resource "azapi_resource" "tracing_connection" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = "appinsights"
  parent_id = var.foundry.project_id
  locks     = [var.foundry.id]
  body = {
    properties = {
      category      = "AppInsights"
      target        = module.monitoring.app_insights_id
      authType      = "ApiKey"
      isSharedToAll = false
      metadata = {
        ApiType    = "Azure"
        ResourceId = module.monitoring.app_insights_id
      }
    }
  }
  sensitive_body = {
    properties = {
      credentials = {
        key = module.monitoring.app_insights_connection_string
      }
    }
  }
}
