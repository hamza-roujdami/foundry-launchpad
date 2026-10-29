locals {
  foundry_name = "foundry-hub-${var.name_suffix}"
  safety_name  = "cs-hub-${var.name_suffix}"
  apim_name    = "apim-ai-hub-${var.name_suffix}"
  api_name     = "foundry"
  deployments = {
    for alias, model in var.models : alias => {
      model    = model.name
      version  = model.version
      sku_name = model.sku_name
      capacity = model.capacity
    }
  }

  # The gateway forwards /v1/... to Foundry's OpenAI v1 API.
  foundry_backend_url = "${module.foundry.endpoint}/openai"

  operations = {
    responses-create        = { name = "Create a response", method = "POST", path = "/v1/responses", params = [] }
    responses-get           = { name = "Get a response", method = "GET", path = "/v1/responses/{response_id}", params = ["response_id"] }
    responses-delete        = { name = "Delete a response", method = "DELETE", path = "/v1/responses/{response_id}", params = ["response_id"] }
    responses-cancel        = { name = "Cancel a background response", method = "POST", path = "/v1/responses/{response_id}/cancel", params = ["response_id"] }
    responses-input-items   = { name = "List input items", method = "GET", path = "/v1/responses/{response_id}/input_items", params = ["response_id"] }
    chat-completions-create = { name = "Create a chat completion", method = "POST", path = "/v1/chat/completions", params = [] }
    embeddings-create       = { name = "Create embeddings", method = "POST", path = "/v1/embeddings", params = [] }
  }

  foundry_dns_zones = var.private_networking ? [
    var.dns_zone_ids["cognitiveservices"],
    var.dns_zone_ids["openai"],
    var.dns_zone_ids["servicesai"],
  ] : []
}

module "monitoring" {
  source = "../monitoring"

  name                = "hub-${var.name_suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  private_networking  = var.private_networking
}

module "foundry" {
  source = "../foundry"

  name                = local.foundry_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  projects            = []

  deployments = local.deployments

  private_networking         = var.private_networking
  private_endpoint_subnet_id = var.private_endpoint_subnet_id
  dns_zone_ids               = local.foundry_dns_zones

  private_endpoint_resource_group_name = var.private_endpoint_resource_group_name
}

resource "azurerm_cognitive_account" "content_safety" {
  count = var.deploy_content_safety ? 1 : 0

  name                          = local.safety_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  kind                          = "ContentSafety"
  sku_name                      = "S0"
  custom_subdomain_name         = local.safety_name
  local_auth_enabled            = false
  public_network_access_enabled = !var.private_networking
  tags                          = var.tags

  network_acls {
    default_action = var.private_networking ? "Deny" : "Allow"
  }
}

module "content_safety_endpoint" {
  source = "../private-endpoint"
  count  = var.private_networking && var.deploy_content_safety ? 1 : 0

  name                = "pe-${local.safety_name}"
  resource_group_name = var.private_endpoint_resource_group_name
  location            = var.location
  tags                = var.tags
  subnet_id           = var.private_endpoint_subnet_id
  target_resource_id  = azurerm_cognitive_account.content_safety[0].id
  subresource_name    = "account"
  dns_zone_ids        = [var.dns_zone_ids["cognitiveservices"]]
}

resource "azurerm_api_management" "this" {
  name                = local.apim_name
  resource_group_name = var.resource_group_name
  location            = var.location
  publisher_name      = "Foundry Launchpad"
  publisher_email     = var.publisher_email
  sku_name            = var.apim_sku_name
  # Azure requires an approved private endpoint before public gateway access can be disabled.
  public_network_access_enabled = true
  virtual_network_type          = var.private_networking ? "External" : "None"
  tags                          = var.tags

  lifecycle {
    ignore_changes = [public_network_access_enabled]
  }

  identity {
    type = "SystemAssigned"
  }

  dynamic "virtual_network_configuration" {
    for_each = var.private_networking ? [var.apim_outbound_subnet_id] : []

    content {
      subnet_id = virtual_network_configuration.value
    }
  }
}

module "gateway_endpoint" {
  source = "../private-endpoint"
  count  = var.private_networking ? 1 : 0

  name                = "pe-${local.apim_name}"
  resource_group_name = var.private_endpoint_resource_group_name
  location            = var.location
  tags                = var.tags
  subnet_id           = var.private_endpoint_subnet_id
  target_resource_id  = azurerm_api_management.this.id
  subresource_name    = "Gateway"
  dns_zone_ids        = [var.dns_zone_ids["apim"]]
}

resource "azapi_update_resource" "gateway_access" {
  type        = "Microsoft.ApiManagement/service@2024-05-01"
  resource_id = azurerm_api_management.this.id
  body = {
    properties = {
      publicNetworkAccess = var.gateway_public_access ? "Enabled" : "Disabled"
    }
  }

  lifecycle {
    replace_triggered_by = [azurerm_api_management.this.id]
  }

  depends_on = [module.gateway_endpoint]
}

# Request metadata only: no bodies are logged.
resource "azurerm_monitor_diagnostic_setting" "gateway" {
  name                           = "gateway-logs"
  target_resource_id             = azurerm_api_management.this.id
  log_analytics_workspace_id     = module.monitoring.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "GatewayLogs"
  }
}

resource "azurerm_api_management_logger" "app_insights" {
  name                = "appinsights"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  resource_id         = module.monitoring.app_insights_id

  application_insights {
    instrumentation_key = module.monitoring.app_insights_instrumentation_key
  }
}

resource "azurerm_api_management_diagnostic" "app_insights" {
  identifier               = "applicationinsights"
  api_management_name      = azurerm_api_management.this.name
  resource_group_name      = var.resource_group_name
  api_management_logger_id = azurerm_api_management_logger.app_insights.id
  always_log_errors        = true
  log_client_ip            = false
  verbosity                = "information"
  sampling_percentage      = 100
  # Required by llm-emit-token-metric to send custom metrics to Application Insights.
  metrics_enabled = true

  frontend_request {
    body_bytes = 0
  }
  frontend_response {
    body_bytes = 0
  }
  backend_request {
    body_bytes = 0
  }
  backend_response {
    body_bytes = 0
  }
}

resource "azurerm_role_assignment" "gateway_to_foundry" {
  scope                = module.foundry.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "gateway_to_content_safety" {
  count = var.deploy_content_safety ? 1 : 0

  scope                = azurerm_cognitive_account.content_safety[0].id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}

# The provider has no managed identity option for a backend, so this one goes through the Azure API.
resource "azapi_resource" "content_safety_backend" {
  count = var.deploy_content_safety ? 1 : 0

  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "content-safety"
  parent_id = azurerm_api_management.this.id

  schema_validation_enabled = false

  body = {
    properties = {
      description = "Azure AI Content Safety"
      url         = azurerm_cognitive_account.content_safety[0].endpoint
      protocol    = "http"
      credentials = {
        managedIdentity = {
          resource = "https://cognitiveservices.azure.com"
        }
      }
    }
  }
}

resource "azurerm_api_management_api" "foundry" {
  name                  = local.api_name
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Foundry"
  path                  = local.api_name
  protocols             = ["https"]
  service_url           = local.foundry_backend_url
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "this" {
  for_each = local.operations

  operation_id        = each.key
  api_name            = azurerm_api_management_api.foundry.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = each.value.name
  method              = each.value.method
  url_template        = each.value.path

  dynamic "template_parameter" {
    for_each = each.value.params

    content {
      name     = template_parameter.value
      required = true
      type     = "string"
    }
  }
}

resource "azurerm_api_management_api_policy" "foundry" {
  api_name            = azurerm_api_management_api.foundry.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name

  xml_content = templatefile("${path.module}/gateway-policy.xml.tftpl", {
    tenant_id                     = var.tenant_id
    client_id                     = var.gateway_client_id
    role                          = var.gateway_role
    tokens_per_minute             = var.tokens_per_minute
    embedding_requests_per_minute = var.embedding_requests_per_minute
    content_safety                = var.deploy_content_safety
    backend_url                   = local.foundry_backend_url
  })

  depends_on = [
    azapi_resource.content_safety_backend,
    azurerm_api_management_api_operation.this,
    azurerm_api_management_diagnostic.app_insights,
  ]
}
