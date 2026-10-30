mock_provider "azurerm" {
  override_during = plan

  mock_resource "azurerm_storage_account" {
    defaults = {
      id                    = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/use-case/providers/Microsoft.Storage/storageAccounts/stlptest01"
      primary_blob_endpoint = "https://stlptest01.blob.core.windows.net/"
    }
  }
  mock_resource "azurerm_search_service" {
    defaults = {
      id       = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/use-case/providers/Microsoft.Search/searchServices/search-test"
      endpoint = "https://search-test.search.windows.net"
    }
  }
  mock_resource "azurerm_cosmosdb_account" {
    defaults = {
      id       = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/use-case/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-test"
      endpoint = "https://cosmos-test.documents.azure.com:443/"
    }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/use-case/providers/Microsoft.KeyVault/vaults/kv-test01"
    }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      principal_id = "44444444-4444-4444-4444-444444444444"
      client_id    = "55555555-5555-5555-5555-555555555555"
    }
  }
  mock_resource "azurerm_container_app_environment" {
    defaults = {
      id                = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/use-case/providers/Microsoft.App/managedEnvironments/test"
      default_domain    = "test.centralus.azurecontainerapps.io"
      static_ip_address = "10.40.4.10"
    }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/network/providers/Microsoft.Network/privateDnsZones/test.centralus.azurecontainerapps.io"
    }
  }
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/use-case/providers/Microsoft.OperationalInsights/workspaces/test-law"
    }
  }
  mock_resource "azurerm_application_insights" {
    defaults = {
      id                = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/use-case/providers/Microsoft.Insights/components/test-appi"
      connection_string = "InstrumentationKey=00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "azapi" {
  override_during = plan
}

variables {
  resource_group_name = "use-case"
  location            = "centralus"
  tags                = { workload = "test" }
  name_suffix         = "test01"
  use_case_name       = "test-use-case"
  gateway = {
    url      = "https://gateway.azure-api.net/foundry/v1"
    audience = "api://55555555-5555-5555-5555-555555555555"
    models   = { fast-chat = { name = "gpt-6.1-sol", version = "2026-09-29" }, advanced-chat = { name = "gpt-6.1-terra", version = "2026-10-26" } }
  }
  tenant_id = "00000000-0000-0000-0000-000000000000"
  registry = {
    id           = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/foundation/providers/Microsoft.ContainerRegistry/registries/shared"
    name         = "shared"
    login_server = "shared.azurecr.io"
  }
  foundry = {
    id                   = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/foundation/providers/Microsoft.CognitiveServices/accounts/shared"
    project_id           = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/foundation/providers/Microsoft.CognitiveServices/accounts/shared/projects/test-use-case"
    project_principal_id = "33333333-3333-3333-3333-333333333333"
    project_endpoint     = "https://shared.services.ai.azure.com/api/projects/test-use-case"
  }
  private_endpoint_resource_group_name = "network"
  private_endpoint_subnet_id           = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/network/providers/Microsoft.Network/virtualNetworks/ai-spokes/subnets/pe"
  aca_subnet_id                        = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/network/providers/Microsoft.Network/virtualNetworks/ai-spokes/subnets/aca-test"
  dns_zone_ids = {
    for key in ["blob", "search", "cosmos", "keyvault"] :
    key => "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/network/providers/Microsoft.Network/privateDnsZones/${key}.example"
  }
  engineer_group_ids = ["66666666-6666-6666-6666-666666666666"]
}

run "private_use_case" {
  command = plan
  module {
    source = "./modules/ai-use-case"
  }
  assert {
    condition     = one([for service in output.private_service_ids : service.api_version if service.id == azurerm_container_app_environment.this.id]) == "2025-07-01"
    error_message = "ACA verification must use an API version exposing publicNetworkAccess."
  }

  assert {
    condition     = azurerm_storage_account.this.account_kind == "StorageV2" && azurerm_storage_account.this.account_tier == "Standard" && azurerm_storage_account.this.account_replication_type == "LRS" && !azurerm_storage_account.this.shared_access_key_enabled && !azurerm_storage_account.this.allow_nested_items_to_be_public && azurerm_storage_account.this.default_to_oauth_authentication && azurerm_storage_account.this.public_network_access == "Disabled"
    error_message = "Storage must remain private, keyless Standard LRS StorageV2."
  }
  assert {
    condition     = !azurerm_search_service.this.local_authentication_enabled && !azurerm_search_service.this.public_network_access_enabled && azurerm_search_service.this.sku == "basic" && azurerm_search_service.this.replica_count == 1 && azurerm_search_service.this.partition_count == 1
    error_message = "Search must remain Entra-only, private and Basic 1x1."
  }
  assert {
    condition     = !azurerm_cosmosdb_account.this.local_authentication_enabled && !azurerm_cosmosdb_account.this.public_network_access_enabled && contains([for capability in azurerm_cosmosdb_account.this.capabilities : capability.name], "EnableServerless") && azurerm_key_vault.this.rbac_authorization_enabled && !azurerm_key_vault.this.public_network_access_enabled
    error_message = "Cosmos must be private, Entra-only and serverless; Key Vault must be private and RBAC-enabled."
  }
  assert {
    condition     = output.backing_services.blob_container == var.use_case_name && output.backing_services.database == var.use_case_name && azurerm_storage_container.application.container_access_type == "private"
    error_message = "The use case must own a private application container and SQL database."
  }
  assert {
    condition     = azurerm_container_app_environment.this.resource_group_name == "use-case" && azurerm_container_app_environment.this.internal_load_balancer_enabled && azurerm_container_app_environment.this.public_network_access == "Disabled" && azurerm_container_app_environment.this.infrastructure_subnet_id == var.aca_subnet_id && length(azurerm_container_app_environment.this.workload_profile) == 1 && one(azurerm_container_app_environment.this.workload_profile).workload_profile_type == "Consumption"
    error_message = "Each use case needs its own internal Consumption environment in its application group."
  }
  assert {
    condition     = azurerm_private_dns_zone.environment.resource_group_name == "network" && azurerm_private_dns_zone.environment.name == azurerm_container_app_environment.this.default_domain && azurerm_private_dns_zone_virtual_network_link.environment.virtual_network_id == split("/subnets/", var.aca_subnet_id)[0] && toset(keys(azurerm_private_dns_a_record.environment)) == toset(["@", "*"]) && alltrue([for record in azurerm_private_dns_a_record.environment : toset(record.records) == toset([azurerm_container_app_environment.this.static_ip_address])])
    error_message = "Environment-specific DNS must link the AI spokes VNet and resolve apex and wildcard internally."
  }
  assert {
    condition     = toset(keys(module.private_endpoint)) == toset(["blob", "search", "cosmos", "keyvault"]) && alltrue([for service in [azurerm_storage_account.this, azurerm_search_service.this, azurerm_cosmosdb_account.this, azurerm_key_vault.this] : service.resource_group_name == "use-case"])
    error_message = "Every backing service must live in the use case with its own private endpoint."
  }
  assert {
    condition     = azapi_resource.tracing_connection.parent_id == var.foundry.project_id && azapi_resource.tracing_connection.type == "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01" && alltrue([for connection in azapi_resource.agent_connection : connection.parent_id == var.foundry.project_id && connection.body.properties.authType == "AAD" && connection.locks == tolist([var.foundry.id])]) && azapi_resource.capability_host["agents"].parent_id == var.foundry.project_id
    error_message = "Connections and capability host must attach to the existing foundation project, never a new use case account."
  }
  assert {
    condition     = azapi_resource.capability_host["agents"].body.properties.storageConnections == ["${var.use_case_name}-agent-files"] && azapi_resource.capability_host["agents"].body.properties.threadStorageConnections == ["${var.use_case_name}-agent-threads"] && azapi_resource.capability_host["agents"].body.properties.vectorStoreConnections == ["${var.use_case_name}-agent-search"] && !azapi_resource.capability_host["agents"].schema_validation_enabled
    error_message = "The capability host must explicitly select all three BYO connections using the documented pinned-schema workaround."
  }
  assert {
    condition     = azurerm_role_assignment.runtime["project"].scope == var.foundry.project_id && azurerm_role_assignment.runtime["registry"].scope == var.registry.id && azurerm_role_assignment.runtime["blob"].scope == "${azurerm_storage_account.this.id}/blobServices/default/containers/${var.use_case_name}" && azurerm_cosmosdb_sql_role_assignment.runtime.scope == "${azurerm_cosmosdb_account.this.id}/dbs/${var.use_case_name}" && alltrue([for assignment in azurerm_role_assignment.engineer : assignment.scope == var.foundry.project_id && assignment.role_definition_name == "Foundry User"])
    error_message = "Runtime and engineer permissions must remain scoped to the project, registry or application data namespace."
  }
  assert {
    condition     = alltrue([for assignment in azurerm_role_assignment.agent_service : assignment.principal_id == var.foundry.project_principal_id && contains([azurerm_storage_account.this.id, azurerm_search_service.this.id, azurerm_cosmosdb_account.this.id], assignment.scope)]) && azurerm_role_assignment.agent_service["cosmos"].role_definition_name == "Cosmos DB Operator" && azurerm_cosmosdb_sql_role_assignment.agent_service["agents"].scope == azurerm_cosmosdb_account.this.id
    error_message = "Agent Service permissions must use the project identity at backing-resource scope, including Cosmos Operator and SQL data access."
  }
  assert {
    condition     = length(output.private_service_ids) == 5 && output.project_principal_id == var.foundry.project_principal_id && output.identity_principal_id != output.project_principal_id && toset(keys(output.monitoring_resource_ids)) == toset(["logs", "traces"]) && length(output.connections) == 5
    error_message = "The infrastructure-only contract must report five private services, separate runtime/project identities and five connections."
  }
  assert {
    condition = (
      azapi_resource.gateway_connection["ai-gateway"].parent_id == var.foundry.project_id &&
      azapi_resource.gateway_connection["ai-gateway"].name == "${var.use_case_name}-ai-gateway" &&
      azapi_resource.tracing_connection.name == "${var.use_case_name}-appinsights" &&
      azapi_resource.gateway_connection["ai-gateway"].body.properties.category == "ApiManagement" &&
      azapi_resource.gateway_connection["ai-gateway"].body.properties.authType == "ProjectManagedIdentity" &&
      azapi_resource.gateway_connection["ai-gateway"].body.properties.target == var.gateway.url &&
      azapi_resource.gateway_connection["ai-gateway"].body.properties.audience == var.gateway.audience &&
      azapi_resource.gateway_connection["ai-gateway"].body.properties.metadata.deploymentInPath == "false" &&
      azapi_resource.gateway_connection["ai-gateway"].body.properties.metadata.inferenceAPIVersion == "v1" &&
      toset([for model in jsondecode(azapi_resource.gateway_connection["ai-gateway"].body.properties.metadata.models) : model.name]) == toset(["fast-chat", "advanced-chat"]) &&
      !contains(keys(azapi_resource.gateway_connection["ai-gateway"].body.properties), "credentials")
    )
    error_message = "The model connection must use the project identity, custom gateway audience and static approved model without keys or direct model access."
  }
}

run "without_agent_infrastructure" {
  command = plan
  module {
    source = "./modules/ai-use-case"
  }
  variables {
    enable_agent_infrastructure = false
    engineer_group_ids          = []
  }
  assert {
    condition     = length(azapi_resource.agent_connection) == 0 && length(azapi_resource.capability_host) == 0 && length(azurerm_role_assignment.agent_service) == 0 && length(azurerm_cosmosdb_sql_role_assignment.agent_service) == 0 && output.capability_host_id == null
    error_message = "Disabling Agent Service infrastructure must remove its connections, service grants and capability host."
  }
  assert {
    condition     = toset(keys(output.connections)) == toset(["appinsights"]) && length(module.private_endpoint) == 4 && length(azurerm_role_assignment.runtime) == 5 && length(azurerm_role_assignment.engineer) == 0
    error_message = "Tracing, private backing endpoints and runtime grants remain without Agent Service infrastructure."
  }
}
