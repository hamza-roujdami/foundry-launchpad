mock_provider "azurerm" {
  mock_resource "azurerm_api_management" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.ApiManagement/service/test"
      identity = [{
        type         = "SystemAssigned"
        principal_id = "11111111-1111-1111-1111-111111111111"
        tenant_id    = "22222222-2222-2222-2222-222222222222"
        identity_ids = []
      }]
    }
  }
  mock_resource "azurerm_cognitive_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.CognitiveServices/accounts/test"
    }
  }
}
mock_provider "azapi" {}

run "private_model_gateway" {
  command = plan
  module {
    source = "./modules/ai-hub-services"
  }

  override_module {
    target = module.foundry
    outputs = {
      name     = "test"
      id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.CognitiveServices/accounts/test"
      endpoint = "https://test.openai.azure.com"
    }
  }
  override_module {
    target = module.monitoring
    outputs = {
      log_analytics_workspace_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test"
      app_insights_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.Insights/components/test"
      app_insights_instrumentation_key = "33333333-3333-3333-3333-333333333333"
    }
  }

  variables {
    resource_group_name                  = "test"
    location                             = "centralus"
    tags                                 = {}
    name_suffix                          = "123456"
    publisher_email                      = "platform@example.com"
    apim_sku_name                        = "StandardV2_1"
    gateway_public_access                = false
    tokens_per_minute                    = 10000
    model                                = { name = "gpt-6-sol", version = "2026-09-22", sku_name = "DataZoneStandard", capacity = 15 }
    deploy_content_safety                = false
    tenant_id                            = "22222222-2222-2222-2222-222222222222"
    gateway_client_id                    = "33333333-3333-3333-3333-333333333333"
    gateway_role                         = "Gateway.Invoke"
    private_networking                   = true
    private_endpoint_resource_group_name = "test"
    private_endpoint_subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.Network/virtualNetworks/test/subnets/pe"
    apim_outbound_subnet_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.Network/virtualNetworks/test/subnets/apim"
    dns_zone_ids = {
      for key in ["apim", "cognitiveservices", "openai", "servicesai"] :
      key => "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test/providers/Microsoft.Network/privateDnsZones/test.example"
    }
  }

  assert {
    condition     = azapi_update_resource.gateway_access.body.properties.publicNetworkAccess == "Disabled"
    error_message = "The post-endpoint update must close public gateway access."
  }
  assert {
    condition     = azurerm_api_management.this.virtual_network_type == "External" && length(module.gateway_endpoint) == 1
    error_message = "The private gateway needs both outbound VNet integration and inbound Private Link."
  }
  assert {
    condition     = length(azurerm_api_management_api_operation.this) == 6 && !azurerm_api_management_api.foundry.subscription_required
    error_message = "The supported inference routes must use Entra authentication without requiring a subscription key."
  }
  assert {
    condition     = strcontains(azurerm_api_management_api_policy.foundry.xml_content, "validate-jwt") && strcontains(azurerm_api_management_api_policy.foundry.xml_content, "authentication-managed-identity") && strcontains(azurerm_api_management_api_policy.foundry.xml_content, "llm-token-limit")
    error_message = "The rendered policy must authenticate callers and the backend and enforce caller token limits."
  }
  assert {
    condition     = length(azurerm_cognitive_account.content_safety) == 0
    error_message = "Content Safety must not be provisioned when disabled."
  }
}
