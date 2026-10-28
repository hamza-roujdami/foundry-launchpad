locals {
  subnet_definitions = {
    private-endpoints = { prefix = cidrsubnet(var.address_space, 10, 0), delegation = null }
    apim-outbound = {
      prefix     = cidrsubnet(var.address_space, 11, 2)
      delegation = { service = "Microsoft.Web/serverFarms", actions = ["Microsoft.Network/virtualNetworks/subnets/action"] }
    }
    foundry-agent = {
      prefix     = cidrsubnet(var.address_space, 8, 192)
      delegation = { service = "Microsoft.App/environments", actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"] }
    }
  }

  selected_subnets = {
    for key, definition in local.subnet_definitions : key => definition
    if key == "private-endpoints" ||
    (var.network_role == "ai_hub" && key == "apim-outbound") ||
    (var.network_role == "ai_spokes" && key == "foundry-agent")
  }
  subnets = merge(local.selected_subnets, var.network_role == "ai_spokes" ? {
    for name, slot in var.use_case_subnet_slots : "aca-${name}" => {
      prefix     = cidrsubnet(var.address_space, 7, slot)
      delegation = { service = "Microsoft.App/environments", actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"] }
    }
  } : {})

  private_dns_zones = {
    apim              = "privatelink.azure-api.net"
    cognitiveservices = "privatelink.cognitiveservices.azure.com"
    openai            = "privatelink.openai.azure.com"
    servicesai        = "privatelink.services.ai.azure.com"
    search            = "privatelink.search.windows.net"
    cosmos            = "privatelink.documents.azure.com"
    blob              = "privatelink.blob.core.windows.net"
    acr               = "privatelink.azurecr.io"
    keyvault          = "privatelink.vaultcore.azure.net"
    monitor           = "privatelink.monitor.azure.com"
    oms               = "privatelink.oms.opinsights.azure.com"
    ods               = "privatelink.ods.opinsights.azure.com"
    automation        = "privatelink.agentsvc.azure-automation.net"
  }
}

resource "azurerm_virtual_network" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = local.subnets

  name                 = "snet-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.prefix]

  # Keeps NSG rules in effect for private endpoint traffic.
  private_endpoint_network_policies = "Enabled"

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]

    content {
      name = "delegation"

      service_delegation {
        name    = delegation.value.service
        actions = delegation.value.actions
      }
    }
  }
}

resource "azurerm_network_security_group" "this" {
  for_each = local.subnets

  name                = "nsg-snet-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = local.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

resource "azurerm_private_dns_zone" "this" {
  for_each = var.existing_dns_zone_ids == null ? local.private_dns_zones : {}

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = var.existing_dns_zone_ids == null ? local.private_dns_zones : {}

  name                = "${var.name}-link"
  private_dns_zone_id = azurerm_private_dns_zone.this[each.key].id
  virtual_network_id  = azurerm_virtual_network.this.id
  tags                = var.tags
}
