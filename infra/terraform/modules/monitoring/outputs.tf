output "log_analytics_workspace_id" {
  description = "Log Analytics use_case."
  value       = azurerm_log_analytics_workspace.this.id
}

output "app_insights_id" {
  description = "Application Insights component."
  value       = azurerm_application_insights.this.id
}

output "app_insights_instrumentation_key" {
  description = "Application Insights instrumentation key."
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "app_insights_connection_string" {
  description = "Application Insights connection string."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
