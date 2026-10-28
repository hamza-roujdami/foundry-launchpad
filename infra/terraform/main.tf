data "azurerm_client_config" "current" {}

locals {
  name_suffix        = substr(sha1("${var.tenant_id}/${var.deployment_name}"), 0, 6)
  gateway_role_value = "Gateway.Invoke"
  ai_hub_group_names = {
    network  = "rg-ai-hub-infra-nonprod-${var.region_code}"
    services = "rg-ai-hub-services-nonprod-${var.region_code}"
  }
  ai_spokes_group_names = {
    network = "rg-ai-spokes-infra-nonprod-${var.region_code}"
  }
  ai_hub_network = var.existing_networks == null ? {
    vnet_id                    = module.ai_hub_network[0].vnet_id
    private_endpoint_subnet_id = module.ai_hub_network[0].private_endpoint_subnet_id
    apim_outbound_subnet_id    = module.ai_hub_network[0].apim_outbound_subnet_id
    dns_zone_ids               = module.ai_hub_network[0].dns_zone_ids
  } : var.existing_networks.ai_hub
  ai_spokes_network = var.existing_networks == null ? {
    vnet_id                    = module.ai_spokes_network[0].vnet_id
    private_endpoint_subnet_id = module.ai_spokes_network[0].private_endpoint_subnet_id
    use_case_aca_subnet_ids    = module.ai_spokes_network[0].use_case_aca_subnet_ids
    foundry_agent_subnet_id    = module.ai_spokes_network[0].foundry_agent_subnet_id
  } : var.existing_networks.ai_spokes
}

resource "azurerm_resource_group" "ai_hub" {
  for_each = local.ai_hub_group_names
  name     = each.value
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "ai_spokes" {
  provider = azurerm.ai_spokes
  for_each = local.ai_spokes_group_names
  name     = each.value
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "ai_use_case" {
  provider = azurerm.ai_spokes
  for_each = var.use_cases

  name     = "rg-${each.key}-dev-${var.region_code}"
  location = var.location
  tags     = merge(var.tags, { use_case = each.key })
}
