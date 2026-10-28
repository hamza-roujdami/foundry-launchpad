output "id" {
  description = "Foundry account."
  value       = azurerm_cognitive_account.this.id
}

output "name" {
  description = "Foundry account name."
  value       = azurerm_cognitive_account.this.name
}

output "endpoint" {
  description = "Azure OpenAI endpoint of the account."
  value       = "https://${azurerm_cognitive_account.this.name}.openai.azure.com"
}

output "project_ids" {
  description = "Project IDs by project name."
  value       = { for name, project in azurerm_cognitive_account_project.this : name => project.id }
  # Capability provisioning needs the private account endpoint ready, not only the ARM project.
  depends_on = [module.private_endpoint]
}

output "project_principal_ids" {
  description = "Object ID of each project's managed identity, by project name."
  value       = { for name, project in azurerm_cognitive_account_project.this : name => project.identity[0].principal_id }
}

output "project_endpoints" {
  description = "Data-plane endpoint of each project, by project name."
  value       = { for name, project in azurerm_cognitive_account_project.this : name => "https://${azurerm_cognitive_account.this.name}.services.ai.azure.com/api/projects/${name}" }
}
