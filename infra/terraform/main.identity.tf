resource "azuread_application" "gateway" {
  display_name     = "foundry-launchpad-${var.deployment_name}-gateway"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azurerm_client_config.current.object_id]

  api {
    requested_access_token_version = 2
  }
  app_role {
    id                   = uuidv5("dns", "${local.gateway_role_value}.${var.deployment_name}")
    value                = local.gateway_role_value
    display_name         = "Invoke the gateway"
    description          = "Call approved Launchpad inference APIs."
    allowed_member_types = ["Application"]
    enabled              = true
  }
  lifecycle {
    ignore_changes = [identifier_uris, service_management_reference]
  }
}

resource "azuread_application_identifier_uri" "gateway" {
  application_id = azuread_application.gateway.id
  identifier_uri = "api://${azuread_application.gateway.client_id}"
}

resource "azuread_service_principal" "gateway" {
  client_id                    = azuread_application.gateway.client_id
  app_role_assignment_required = true
  owners                       = [data.azurerm_client_config.current.object_id]
}

resource "azuread_app_role_assignment" "runtime" {
  for_each = module.ai_use_case

  app_role_id         = azuread_service_principal.gateway.app_role_ids[local.gateway_role_value]
  principal_object_id = each.value.identity_principal_id
  resource_object_id  = azuread_service_principal.gateway.object_id
}

resource "azuread_app_role_assignment" "project" {
  for_each = var.enable_agent_infrastructure ? module.ai_use_case : {}

  app_role_id         = azuread_service_principal.gateway.app_role_ids[local.gateway_role_value]
  principal_object_id = each.value.project_principal_id
  resource_object_id  = azuread_service_principal.gateway.object_id
}
