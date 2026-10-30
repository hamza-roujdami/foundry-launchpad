output "identity_principal_id" {
  description = "Use-case runtime managed identity object ID."
  value       = azurerm_user_assigned_identity.runtime.principal_id
}

output "identity_client_id" {
  description = "Use-case runtime managed identity client ID."
  value       = azurerm_user_assigned_identity.runtime.client_id
}

output "project_principal_id" {
  description = "Existing Foundry project system-assigned identity object ID."
  value       = var.foundry.project_principal_id
}

output "project_endpoint" {
  description = "Existing Foundry project endpoint for project operations; model traffic must use the hub gateway."
  value       = var.foundry.project_endpoint
}

output "environment_id" {
  description = "Private use case ACA environment ID for subsequent application deployments."
  value       = azurerm_container_app_environment.this.id
}

output "backing_services" {
  description = "Private backing-service endpoints and application-owned data namespaces."
  value = {
    storage_url    = azurerm_storage_account.this.primary_blob_endpoint
    search_url     = azurerm_search_service.this.endpoint
    cosmos_url     = azurerm_cosmosdb_account.this.endpoint
    vault_url      = azurerm_key_vault.this.vault_uri
    blob_container = azurerm_storage_container.application.name
    database       = azurerm_cosmosdb_sql_database.application.name
  }
}

output "monitoring_resource_ids" {
  description = "Use-case logs and traces resource IDs for association with the root AMPLS."
  value = {
    logs   = module.monitoring.log_analytics_workspace_id
    traces = module.monitoring.app_insights_id
  }
}

output "private_service_ids" {
  description = "Use-case-owned private PaaS resources and API versions for verification; shared resources are reported by the foundation."
  value = [
    { id = azurerm_storage_account.this.id, api_version = "2023-05-01" },
    { id = azurerm_search_service.this.id, api_version = "2025-05-01" },
    { id = azurerm_cosmosdb_account.this.id, api_version = "2024-08-15" },
    { id = azurerm_key_vault.this.id, api_version = "2023-07-01" },
    { id = azurerm_container_app_environment.this.id, api_version = "2025-07-01" },
  ]
}

output "capability_host_id" {
  description = "Agent Service capability host ID, or null when optional agent infrastructure is disabled."
  value       = var.enable_agent_infrastructure ? azapi_resource.capability_host["agents"].id : null
}

output "connections" {
  description = "Project connection IDs for tracing and, when enabled, backing services and the central model gateway."
  value = merge(
    { appinsights = azapi_resource.tracing_connection.id },
    { for key, connection in azapi_resource.agent_connection : key => connection.id },
    { for key, connection in azapi_resource.gateway_connection : key => connection.id }
  )
}
