module "ai_use_case" {
  for_each = var.use_cases

  source = "./modules/ai-use-case"
  providers = {
    azurerm = azurerm.ai_spokes
    azapi   = azapi.ai_spokes
  }

  resource_group_name         = azurerm_resource_group.ai_use_case[each.key].name
  location                    = var.location
  tags                        = var.tags
  name_suffix                 = substr(sha1("${local.name_suffix}/${each.key}"), 0, 6)
  tenant_id                   = var.tenant_id
  engineer_group_ids          = var.engineer_group_ids
  enable_agent_infrastructure = var.enable_agent_infrastructure
  use_case_name               = each.key
  registry = {
    id           = azurerm_container_registry.ai_spokes.id
    name         = azurerm_container_registry.ai_spokes.name
    login_server = azurerm_container_registry.ai_spokes.login_server
  }
  foundry = {
    id                   = module.ai_spokes_foundry.id
    project_id           = module.ai_spokes_foundry.project_ids[each.key]
    project_principal_id = module.ai_spokes_foundry.project_principal_ids[each.key]
    project_endpoint     = module.ai_spokes_foundry.project_endpoints[each.key]
  }
  private_endpoint_resource_group_name = azurerm_resource_group.ai_spokes["network"].name
  private_endpoint_subnet_id           = local.ai_spokes_network.private_endpoint_subnet_id
  aca_subnet_id                        = local.ai_spokes_network.use_case_aca_subnet_ids[each.key]
  dns_zone_ids                         = local.ai_hub_network.dns_zone_ids
}
