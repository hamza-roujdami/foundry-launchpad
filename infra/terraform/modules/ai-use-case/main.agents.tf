locals {
  agent_connections = var.enable_agent_infrastructure ? {
    blob = {
      name     = "agent-files"
      category = "AzureStorageAccount"
      target   = azurerm_storage_account.this.primary_blob_endpoint
    }
    search = {
      name     = "agent-search"
      category = "CognitiveSearch"
      target   = azurerm_search_service.this.endpoint
    }
    cosmos = {
      name     = "agent-threads"
      category = "CosmosDb"
      target   = azurerm_cosmosdb_account.this.endpoint
    }
  } : {}
  agent_roles = var.enable_agent_infrastructure ? {
    blob = {
      scope = azurerm_storage_account.this.id
      role  = "Storage Blob Data Owner"
    }
    cosmos = {
      scope = azurerm_cosmosdb_account.this.id
      role  = "Cosmos DB Operator"
    }
    search = {
      scope = azurerm_search_service.this.id
      role  = "Search Service Contributor"
    }
    search-data = {
      scope = azurerm_search_service.this.id
      role  = "Search Index Data Contributor"
    }
  } : {}
}

resource "azapi_resource" "gateway_connection" {
  for_each = var.enable_agent_infrastructure ? toset(["ai-gateway"]) : toset([])

  # Microsoft's APIM connection sample uses this contract; embedded schemas omit ProjectManagedIdentity.
  schema_validation_enabled = false
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = each.key
  parent_id                 = var.foundry.project_id
  locks                     = [var.foundry.id]
  body = {
    properties = {
      category      = "ApiManagement"
      target        = var.gateway.url
      authType      = "ProjectManagedIdentity"
      audience      = var.gateway.audience
      isSharedToAll = false
      metadata = {
        deploymentInPath    = "false"
        inferenceAPIVersion = "v1"
        models = jsonencode([for alias, model in var.gateway.models : {
          name = alias
          properties = {
            model = {
              name    = model.name
              version = model.version
              format  = "OpenAI"
            }
          }
        }])
      }
    }
  }
}

resource "azapi_resource" "agent_connection" {
  for_each = local.agent_connections

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = each.value.name
  parent_id = var.foundry.project_id
  locks     = [var.foundry.id]
  body = {
    properties = {
      category = each.value.category
      target   = each.value.target
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = local.backing_endpoints[each.key].id
        location   = var.location
      }
    }
  }
}

resource "azurerm_role_assignment" "agent_service" {
  for_each = local.agent_roles

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = var.foundry.project_principal_id
}

resource "azurerm_cosmosdb_sql_role_assignment" "agent_service" {
  for_each = var.enable_agent_infrastructure ? toset(["agents"]) : toset([])

  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
  role_definition_id  = "${azurerm_cosmosdb_account.this.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = var.foundry.project_principal_id
  # Agent Service creates and owns its internal databases, outside the application namespace.
  scope = azurerm_cosmosdb_account.this.id
}

resource "azapi_resource" "capability_host" {
  for_each = var.enable_agent_infrastructure ? toset(["agents"]) : toset([])

  # Standard setup requires capabilityHostKind, absent from the pinned AzAPI 2.13 embedded schema.
  schema_validation_enabled = false
  type                      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name                      = each.key
  parent_id                 = var.foundry.project_id
  locks                     = [var.foundry.id]
  body = {
    properties = {
      capabilityHostKind       = "Agents"
      storageConnections       = [azapi_resource.agent_connection["blob"].name]
      threadStorageConnections = [azapi_resource.agent_connection["cosmos"].name]
      vectorStoreConnections   = [azapi_resource.agent_connection["search"].name]
    }
  }

  timeouts {
    create = "60m"
  }

  depends_on = [
    azurerm_role_assignment.agent_service,
    azurerm_cosmosdb_sql_role_assignment.agent_service,
    module.private_endpoint,
  ]
}
