output "gateway_url" {
  description = "Private AI gateway base URL."
  value       = module.ai_hub_services.gateway_url
}

output "gateway_client_id" {
  description = "Entra application audience; callers request api://<id>/.default."
  value       = azuread_application.gateway.client_id
}

output "project_endpoints" {
  description = "Private Foundry project endpoints; no agent is deployed."
  value       = module.ai_spokes_foundry.project_endpoints
}

output "runtime_identities" {
  description = "User-assigned client IDs reserved for future application deployments."
  value       = { for name, use_case in module.ai_use_case : name => use_case.identity_client_id }
}

output "backing_services" {
  description = "AI use-case data endpoints and workload namespaces."
  value       = { for name, use_case in module.ai_use_case : name => use_case.backing_services }
}

output "container_app_environment_ids" {
  description = "Dedicated ACA environment per use case. No app or job is deployed."
  value       = { for name, use_case in module.ai_use_case : name => use_case.environment_id }
}

output "registry_name" {
  description = "Private shared AI spokes registry."
  value       = azurerm_container_registry.ai_spokes.name
}

output "readiness" {
  description = "Non-secret input for infra/scripts/smoke.py. Export only this output, not the complete Terraform state."
  value = [for name, use_case in module.ai_use_case : {
    name             = name
    project_id       = module.ai_spokes_foundry.project_ids[name]
    project_endpoint = use_case.project_endpoint
    private_urls     = [for key in ["storage_url", "search_url", "cosmos_url", "vault_url"] : use_case.backing_services[key]]
    gateway_url      = "${module.ai_hub_services.gateway_url}/v1"
    gateway_audience = "api://${azuread_application.gateway.client_id}"
    gateway_id       = module.ai_hub_services.apim_id
    connection_name  = "ai-gateway"
    model            = "fast-chat"
    agent_model      = "ai-gateway/fast-chat"
    agents_enabled   = var.enable_agent_infrastructure
    registry_url     = "https://${azurerm_container_registry.ai_spokes.login_server}"
  }]
}

output "verification" {
  description = "Non-secret control-plane contract consumed by infra/terraform/verify.sh."
  value = {
    tenant_id = var.tenant_id
    subscriptions = {
      ai_hub    = var.ai_hub_subscription_id
      ai_spokes = var.ai_spokes_subscription_id
    }
    resource_groups = merge(
      { for key, group in azurerm_resource_group.ai_hub : "ai-hub-${key}" => { name = group.name, subscription_id = var.ai_hub_subscription_id } },
      { for key, group in azurerm_resource_group.ai_spokes : "ai-spokes-${key}" => { name = group.name, subscription_id = var.ai_spokes_subscription_id } },
      { for key, group in azurerm_resource_group.ai_use_case : "ai-use-case-${key}" => { name = group.name, subscription_id = var.ai_spokes_subscription_id } }
    )
    vnets = {
      ai_hub = {
        id                  = local.ai_hub_network.vnet_id
        subscription_id     = var.ai_hub_subscription_id
        resource_group_name = split("/", local.ai_hub_network.vnet_id)[4]
        name                = split("/", local.ai_hub_network.vnet_id)[8]
      }
      ai_spokes = {
        id                  = local.ai_spokes_network.vnet_id
        subscription_id     = var.ai_spokes_subscription_id
        resource_group_name = split("/", local.ai_spokes_network.vnet_id)[4]
        name                = split("/", local.ai_spokes_network.vnet_id)[8]
      }
    }
    private_services = concat(module.ai_hub_services.private_service_ids, [
      { id = module.ai_spokes_foundry.id, api_version = "2025-06-01" },
      { id = azurerm_container_registry.ai_spokes.id, api_version = "2023-07-01" },
    ], flatten([for use_case in values(module.ai_use_case) : use_case.private_service_ids]))
    capability_hosts = var.enable_agent_infrastructure ? [
      for use_case in values(module.ai_use_case) : { id = use_case.capability_host_id, api_version = "2025-04-01-preview" }
    ] : []
    monitoring_services = [
      for id in values(local.monitoring_resource_ids) : {
        id          = id
        api_version = strcontains(lower(id), "operationalinsights") ? "2023-09-01" : "2020-02-02"
      }
    ]
    private_endpoint_groups = [
      { name = azurerm_resource_group.ai_hub["network"].name, subscription_id = var.ai_hub_subscription_id, expected_count = 4 },
      { name = azurerm_resource_group.ai_spokes["network"].name, subscription_id = var.ai_spokes_subscription_id, expected_count = 2 + 4 * length(var.use_cases) },
    ]
    managed_networks = var.existing_networks == null
    dns_zone_ids     = distinct(values(local.ai_hub_network.dns_zone_ids))
    ampls_id         = azurerm_monitor_private_link_scope.this.id
    models           = [for id in values(module.ai_hub_services.model_deployment_ids) : { id = id, api_version = "2025-06-01" }]
  }
}

locals {
  monitoring_resource_ids = merge(module.ai_hub_services.monitoring_resource_ids, {
    ai_spokes_logs   = module.ai_spokes_monitoring.log_analytics_workspace_id
    ai_spokes_traces = module.ai_spokes_monitoring.app_insights_id
    }, merge([
      for name, use_case in module.ai_use_case : {
        for key, id in use_case.monitoring_resource_ids : "${name}-${key}" => id
      }
  ]...))
}
