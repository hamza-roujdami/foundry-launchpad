output "gateway_url" {
  description = "Base URL of the private gateway API."
  value       = "${azurerm_api_management.this.gateway_url}/${local.api_name}"
  depends_on  = [azapi_update_resource.gateway_access]
}

output "apim_name" {
  description = "API Management instance."
  value       = azurerm_api_management.this.name
}

output "apim_id" {
  description = "Gateway resource ID for scoped monitoring and verification."
  value       = azurerm_api_management.this.id
}

output "foundry_account_name" {
  description = "Foundry account containing model deployments."
  value       = module.foundry.name
}

output "monitoring_resource_ids" {
  description = "Hub workspace and Application Insights IDs for AMPLS."
  value = {
    hub_logs   = module.monitoring.log_analytics_workspace_id
    hub_traces = module.monitoring.app_insights_id
  }
}

output "private_service_ids" {
  description = "Private PaaS resources and API versions for read-only verification."
  value = concat([
    { id = azurerm_api_management.this.id, api_version = "2024-05-01" },
    { id = module.foundry.id, api_version = "2025-06-01" },
  ], [for account in azurerm_cognitive_account.content_safety : { id = account.id, api_version = "2025-06-01" }])
}

output "model_deployment_ids" {
  description = "ARM deployment IDs keyed by governed alias, not inference endpoints."
  value       = { for alias in keys(var.models) : alias => "${module.foundry.id}/deployments/${alias}" }
}
