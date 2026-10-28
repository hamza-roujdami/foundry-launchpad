resource "azurerm_monitor_private_link_scope" "this" {
  name                  = "ampls-${local.name_suffix}"
  resource_group_name   = azurerm_resource_group.ai_hub["network"].name
  ingestion_access_mode = "PrivateOnly"
  query_access_mode     = "PrivateOnly"
  tags                  = var.tags
}

resource "azurerm_monitor_private_link_scoped_service" "this" {
  for_each = local.monitoring_resource_ids

  name                = each.key
  resource_group_name = azurerm_resource_group.ai_hub["network"].name
  scope_name          = azurerm_monitor_private_link_scope.this.name
  linked_resource_id  = each.value
}

module "monitoring_endpoint" {
  source = "./modules/private-endpoint"

  name                = "pe-monitor-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.ai_hub["network"].name
  location            = var.location
  tags                = var.tags
  subnet_id           = local.ai_hub_network.private_endpoint_subnet_id
  target_resource_id  = azurerm_monitor_private_link_scope.this.id
  subresource_name    = "azuremonitor"
  dns_zone_ids        = [for key in ["monitor", "oms", "ods", "automation", "blob"] : local.ai_hub_network.dns_zone_ids[key]]

  depends_on = [azurerm_monitor_private_link_scoped_service.this]
}
