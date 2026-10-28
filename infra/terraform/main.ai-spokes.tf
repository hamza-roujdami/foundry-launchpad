module "ai_spokes_network" {
  count = var.existing_networks == null ? 1 : 0

  source = "./modules/network"
  providers = {
    azurerm = azurerm.ai_spokes
  }

  resource_group_name   = azurerm_resource_group.ai_spokes["network"].name
  location              = var.location
  tags                  = var.tags
  name                  = "vnet-ai-spokes-nonprod-${var.region_code}-${local.name_suffix}"
  address_space         = var.ai_spokes_address_space
  network_role          = "ai_spokes"
  use_case_subnet_slots = var.use_case_subnet_slots
  existing_dns_zone_ids = module.ai_hub_network[0].dns_zone_ids
}

module "ai_spokes_monitoring" {
  source = "./modules/monitoring"
  providers = {
    azurerm = azurerm.ai_spokes
  }

  name                = "spokes-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.ai_spokes["network"].name
  location            = var.location
  tags                = var.tags
  private_networking  = true
}

module "ai_spokes_foundry" {
  source = "./modules/foundry"
  providers = {
    azurerm = azurerm.ai_spokes
    azapi   = azapi.ai_spokes
  }

  name                                 = "foundry-spokes-${local.name_suffix}"
  resource_group_name                  = azurerm_resource_group.ai_spokes["network"].name
  location                             = var.location
  tags                                 = var.tags
  projects                             = var.use_cases
  private_networking                   = true
  private_endpoint_subnet_id           = local.ai_spokes_network.private_endpoint_subnet_id
  private_endpoint_resource_group_name = azurerm_resource_group.ai_spokes["network"].name
  agent_subnet_id                      = var.enable_agent_infrastructure ? local.ai_spokes_network.foundry_agent_subnet_id : null
  dns_zone_ids                         = [for key in ["cognitiveservices", "openai", "servicesai"] : local.ai_hub_network.dns_zone_ids[key]]
}

resource "azurerm_container_registry" "ai_spokes" {
  provider = azurerm.ai_spokes

  name                                         = "acrlaunchpad${local.name_suffix}"
  resource_group_name                          = azurerm_resource_group.ai_spokes["network"].name
  location                                     = var.location
  sku                                          = "Premium"
  admin_enabled                                = false
  public_network_access_enabled                = false
  azuread_authentication_as_arm_policy_enabled = true
  tags                                         = var.tags
}

module "ai_spokes_registry_endpoint" {
  source = "./modules/private-endpoint"
  providers = {
    azurerm = azurerm.ai_spokes
  }

  name                = "pe-acr-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.ai_spokes["network"].name
  location            = var.location
  tags                = var.tags
  subnet_id           = local.ai_spokes_network.private_endpoint_subnet_id
  target_resource_id  = azurerm_container_registry.ai_spokes.id
  subresource_name    = "registry"
  dns_zone_ids        = [local.ai_hub_network.dns_zone_ids["acr"]]
}
