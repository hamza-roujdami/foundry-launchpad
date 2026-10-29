module "ai_hub_network" {
  count = var.existing_networks == null ? 1 : 0

  source = "./modules/network"

  resource_group_name = azurerm_resource_group.ai_hub["network"].name
  location            = var.location
  tags                = var.tags
  name                = "vnet-ai-hub-nonprod-${var.region_code}-${local.name_suffix}"
  address_space       = var.ai_hub_address_space
  network_role        = "ai_hub"
}

module "ai_hub_services" {
  source = "./modules/ai-hub-services"

  resource_group_name                  = azurerm_resource_group.ai_hub["services"].name
  location                             = var.location
  tags                                 = var.tags
  name_suffix                          = local.name_suffix
  publisher_email                      = var.publisher_email
  apim_sku_name                        = "StandardV2_1"
  gateway_public_access                = false
  tokens_per_minute                    = var.tokens_per_minute
  models                               = var.models
  embedding_requests_per_minute        = var.embedding_requests_per_minute
  deploy_content_safety                = true
  tenant_id                            = var.tenant_id
  gateway_client_id                    = azuread_application.gateway.client_id
  gateway_role                         = local.gateway_role_value
  private_networking                   = true
  private_endpoint_subnet_id           = local.ai_hub_network.private_endpoint_subnet_id
  private_endpoint_resource_group_name = azurerm_resource_group.ai_hub["network"].name
  apim_outbound_subnet_id              = local.ai_hub_network.apim_outbound_subnet_id
  dns_zone_ids                         = local.ai_hub_network.dns_zone_ids
}
