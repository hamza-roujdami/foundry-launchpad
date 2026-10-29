mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "33333333-3333-3333-3333-333333333333"
    }
  }
}
mock_provider "azurerm" {
  alias = "ai_spokes"
}
mock_provider "azapi" {}
mock_provider "azapi" {
  alias = "ai_spokes"
}
mock_provider "azuread" {
  mock_resource "azuread_application" {
    defaults = {
      id        = "/applications/33333333-3333-3333-3333-333333333333"
      client_id = "33333333-3333-3333-3333-333333333333"
    }
  }
  mock_resource "azuread_service_principal" {
    defaults = {
      object_id = "44444444-4444-4444-4444-444444444444"
      app_role_ids = {
        "Gateway.Invoke" = "55555555-5555-5555-5555-555555555555"
      }
    }
  }
}

variables {
  tenant_id                 = "00000000-0000-0000-0000-000000000000"
  ai_hub_subscription_id    = "11111111-1111-1111-1111-111111111111"
  ai_spokes_subscription_id = "22222222-2222-2222-2222-222222222222"
  publisher_email           = "platform@example.com"
  use_cases                 = ["ai-app-01", "ai-app-02"]
  region_code               = "cus"
  existing_networks         = null
  operations = {
    email             = "operations@example.com"
    budget_start_date = "2026-10-01T00:00:00Z"
    monthly_budgets   = { hub_infra = 100, hub_services = 1000, spokes_infra = 150, per_app = 200 }
  }
}

override_module {
  target = module.ai_hub_network
  outputs = {
    vnet_id                    = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/platform/providers/Microsoft.Network/virtualNetworks/platform"
    vnet_name                  = "ai_hub"
    private_endpoint_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/platform/providers/Microsoft.Network/virtualNetworks/platform/subnets/pe"
    apim_outbound_subnet_id    = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/platform/providers/Microsoft.Network/virtualNetworks/platform/subnets/apim"
    dns_zone_ids = {
      acr = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/platform/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
    }
  }
}

override_module {
  target = module.ai_spokes_network
  outputs = {
    vnet_id                    = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.Network/virtualNetworks/engineering"
    vnet_name                  = "ai_spokes"
    private_endpoint_subnet_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.Network/virtualNetworks/engineering/subnets/pe"
    use_case_aca_subnet_ids = {
      for name in ["ai-app-01", "ai-app-02"] : name => "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.Network/virtualNetworks/engineering/subnets/aca-${name}"
    }
    foundry_agent_subnet_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.Network/virtualNetworks/engineering/subnets/agents"
  }
}

override_module {
  target = module.ai_hub_services
  outputs = {
    gateway_url             = "https://test.azure-api.net/foundry"
    apim_id                 = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/models/providers/Microsoft.ApiManagement/service/test"
    monitoring_resource_ids = {}
    private_service_ids     = []
    model_deployment_ids    = { for alias in ["fast-chat", "advanced-chat", "embeddings"] : alias => "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/models/providers/Microsoft.CognitiveServices/accounts/models/deployments/${alias}" }
  }
}

override_module {
  target = module.ai_use_case
  outputs = {
    identity_principal_id   = "66666666-6666-6666-6666-666666666666"
    identity_client_id      = "77777777-7777-7777-7777-777777777777"
    project_principal_id    = "88888888-8888-8888-8888-888888888888"
    monitoring_resource_ids = {}
    private_service_ids     = []
    project_endpoint        = "https://shared.services.ai.azure.com/api/projects/test"
    backing_services        = { storage_url = "https://test.blob.core.windows.net", search_url = "https://test.search.windows.net", cosmos_url = "https://test.documents.azure.com", vault_url = "https://test.vault.azure.net" }
    environment_id          = "test"
    capability_host_id      = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.CognitiveServices/accounts/shared/projects/test/capabilityHosts/agents"
  }
}

override_module {
  target  = module.monitoring_endpoint
  outputs = {}
}

override_module {
  target = module.ai_spokes_foundry
  outputs = {
    id                    = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.CognitiveServices/accounts/shared"
    name                  = "shared"
    project_ids           = { for name in ["ai-app-01", "ai-app-02"] : name => "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.CognitiveServices/accounts/shared/projects/${name}" }
    project_principal_ids = {}
    project_endpoints     = {}
  }
}

override_module {
  target = module.ai_spokes_monitoring
  outputs = {
    log_analytics_workspace_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.OperationalInsights/workspaces/shared"
    app_insights_id            = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.Insights/components/shared"
  }
}

run "two_subscription_foundation" {
  command = plan
  assert {
    condition = length(output.readiness) == 2 && alltrue([
      for entry in output.readiness : (
        toset(keys(entry)) == toset(["name", "project_id", "project_endpoint", "private_urls", "gateway_url", "gateway_audience", "gateway_id", "connection_name", "model", "agent_model", "agents_enabled", "registry_url"]) &&
        entry.gateway_url == "https://test.azure-api.net/foundry/v1" &&
        entry.agent_model == "${entry.name}-ai-gateway/fast-chat" &&
        length(entry.private_urls) == 4
      )
    ])
    error_message = "Both use cases must export the same complete smoke contract as Bicep, using only the gateway model."
  }
  assert {
    condition = (
      length(azurerm_consumption_budget_resource_group.hub) == 2 &&
      length(azurerm_consumption_budget_resource_group.spokes) == 3 &&
      length(azurerm_monitor_metric_alert.gateway) == 2 &&
      azurerm_monitor_action_group.operations.email_receiver[0].email_address == var.operations.email &&
      azurerm_monitor_metric_alert.gateway["errors"].criteria[0].threshold == 5 &&
      azurerm_monitor_metric_alert.gateway["throttles"].criteria[0].threshold == 10 &&
      alltrue([for budget in azurerm_consumption_budget_resource_group.hub : toset([for notice in budget.notification : notice.threshold]) == toset([80, 100])])
    )
    error_message = "Provide five RG budgets, two gateway alerts and approved email notifications without subscription-wide budgets."
  }
  assert {
    condition     = output.verification.managed_networks && length(output.verification.dns_zone_ids) == 1
    error_message = "Verification must check managed topology and only the explicitly supplied DNS zones."
  }
  assert {
    condition     = length(azurerm_resource_group.ai_hub) == 2 && length(azurerm_resource_group.ai_spokes) == 1 && length(azurerm_resource_group.ai_use_case) == 2
    error_message = "Create two hub groups, one spokes foundation and two use-case groups."
  }
  assert {
    condition     = azurerm_resource_group.ai_hub["network"].name == "rg-ai-hub-infra-nonprod-cus" && azurerm_resource_group.ai_hub["services"].name == "rg-ai-hub-services-nonprod-cus" && azurerm_resource_group.ai_spokes["network"].name == "rg-ai-spokes-infra-nonprod-cus" && azurerm_resource_group.ai_use_case["ai-app-01"].name == "rg-ai-app-01-dev-cus" && azurerm_resource_group.ai_use_case["ai-app-02"].name == "rg-ai-app-02-dev-cus"
    error_message = "Group names must reflect the agreed ownership and environment."
  }
  assert {
    condition     = length(azurerm_virtual_network_peering.ai_hub_to_ai_spokes) == 1 && length(azurerm_virtual_network_peering.ai_spokes_to_ai_hub) == 1
    error_message = "New networks require bilateral subscription-scoped peering."
  }
  assert {
    condition     = output.verification.subscriptions.ai_hub != output.verification.subscriptions.ai_spokes && output.verification.tenant_id == var.tenant_id
    error_message = "Verification must preserve explicit tenant and subscription boundaries."
  }
}

run "invalid_budget_amount" {
  command = plan
  variables {
    operations = {
      email             = "operations@example.com"
      budget_start_date = "2026-10-01T00:00:00Z"
      monthly_budgets   = { hub_infra = 0, hub_services = 1000, spokes_infra = 150, per_app = 200 }
    }
  }
  expect_failures = [var.operations]
}

run "invalid_budget_date" {
  command = plan
  variables {
    operations = {
      email             = "operations@example.com"
      budget_start_date = "2026-10-15T00:00:00Z"
      monthly_budgets   = { hub_infra = 100, hub_services = 1000, spokes_infra = 150, per_app = 200 }
    }
  }
  expect_failures = [var.operations]
}

run "subscriptions_must_differ" {
  command = plan
  variables {
    ai_spokes_subscription_id = "11111111-1111-1111-1111-111111111111"
  }
  expect_failures = [var.ai_spokes_subscription_id]
}

run "invalid_use_case" {
  command = plan
  variables {
    use_cases = ["Team_A"]
  }
  expect_failures = [var.use_cases]
}

run "use_case_must_start_with_letter" {
  command = plan
  variables {
    use_cases = ["1-agent"]
  }
  expect_failures = [var.use_cases]
}

run "use_case_name_too_long" {
  command = plan
  variables {
    use_cases = ["abcdefghijklmnopqrstuvwxyzabcdef"]
  }
  expect_failures = [var.use_cases]
}

run "invalid_capacity" {
  command = plan
  variables {
    models = { for alias in ["fast-chat", "advanced-chat", "embeddings"] : alias => { name = "test", version = "1", sku_name = "Standard", capacity = 0 } }
  }
  expect_failures = [var.models]
}

run "invalid_model_aliases" {
  command = plan
  variables {
    models = { other = { name = "test", version = "1", sku_name = "Standard", capacity = 10 } }
  }
  expect_failures = [var.models]
}

run "invalid_embedding_limit" {
  command = plan
  variables {
    embedding_requests_per_minute = 0
  }
  expect_failures = [var.embedding_requests_per_minute]
}

run "invalid_token_limit" {
  command = plan
  variables {
    tokens_per_minute = 1.5
  }
  expect_failures = [var.tokens_per_minute]
}

run "overlapping_networks" {
  command = plan
  variables {
    ai_spokes_address_space = "10.40.0.0/16"
  }
  expect_failures = [var.ai_spokes_address_space]
}

run "existing_ai_networks" {
  command = plan
  variables {
    existing_networks = {
      ai_hub = {
        vnet_id                    = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/platform/providers/Microsoft.Network/virtualNetworks/platform"
        private_endpoint_subnet_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/platform/providers/Microsoft.Network/virtualNetworks/platform/subnets/pe"
        apim_outbound_subnet_id    = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/platform/providers/Microsoft.Network/virtualNetworks/platform/subnets/apim"
        dns_zone_ids = {
          for key in ["apim", "cognitiveservices", "openai", "servicesai", "acr", "keyvault", "blob", "search", "cosmos", "monitor", "oms", "ods", "automation"] :
          key => "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/platform/providers/Microsoft.Network/privateDnsZones/test.example"
        }
      }
      ai_spokes = {
        vnet_id                    = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.Network/virtualNetworks/engineering"
        private_endpoint_subnet_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.Network/virtualNetworks/engineering/subnets/pe"
        use_case_aca_subnet_ids = {
          for name in ["ai-app-01", "ai-app-02"] : name => "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.Network/virtualNetworks/engineering/subnets/aca-${name}"
        }
        foundry_agent_subnet_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/engineering/providers/Microsoft.Network/virtualNetworks/engineering/subnets/agents"
      }
    }
  }
  assert {
    condition     = length(module.ai_hub_network) == 0 && length(module.ai_spokes_network) == 0 && length(azurerm_private_dns_zone_virtual_network_link.ai_spokes) == 0 && length(azurerm_virtual_network_peering.ai_hub_to_ai_spokes) == 0
    error_message = "Existing-network mode must not adopt ownership of platform VNets, shared DNS links or peerings."
  }
  assert {
    condition     = !output.verification.managed_networks && length(output.verification.dns_zone_ids) == 1
    error_message = "Existing-network verification must retain explicit DNS IDs without assuming managed routing."
  }
}
