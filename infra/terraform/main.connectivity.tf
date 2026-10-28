resource "azurerm_virtual_network_peering" "ai_hub_to_ai_spokes" {
  count = var.existing_networks == null ? 1 : 0

  name                      = "to-ai-spokes"
  resource_group_name       = azurerm_resource_group.ai_hub["network"].name
  virtual_network_name      = module.ai_hub_network[0].vnet_name
  remote_virtual_network_id = module.ai_spokes_network[0].vnet_id
}

resource "azurerm_virtual_network_peering" "ai_spokes_to_ai_hub" {
  provider = azurerm.ai_spokes
  count    = var.existing_networks == null ? 1 : 0

  name                      = "to-ai-hub"
  resource_group_name       = azurerm_resource_group.ai_spokes["network"].name
  virtual_network_name      = module.ai_spokes_network[0].vnet_name
  remote_virtual_network_id = module.ai_hub_network[0].vnet_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "ai_spokes" {
  for_each = var.existing_networks == null ? module.ai_hub_network[0].dns_zone_ids : {}

  name                = "ai-spokes-${local.name_suffix}"
  private_dns_zone_id = each.value
  virtual_network_id  = module.ai_spokes_network[0].vnet_id
  tags                = var.tags
}
