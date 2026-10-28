resource "azurerm_cognitive_account" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = var.name
  project_management_enabled    = true
  local_auth_enabled            = false
  public_network_access_enabled = !var.private_networking
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = var.private_networking ? "Deny" : "Allow"
  }

  # Hosted agents run in this subnet. It can only be set when the account is created.
  dynamic "network_injection" {
    for_each = var.agent_subnet_id == null ? [] : [var.agent_subnet_id]

    content {
      scenario  = "agent"
      subnet_id = network_injection.value
    }
  }
}

resource "azurerm_cognitive_account_project" "this" {
  for_each = var.projects

  name                 = each.key
  cognitive_account_id = azurerm_cognitive_account.this.id
  location             = var.location
  display_name         = each.key
  tags                 = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# The account takes one write at a time, so the deployments wait for the projects.
resource "azurerm_cognitive_deployment" "this" {
  for_each = var.deployments

  name                 = each.key
  cognitive_account_id = azurerm_cognitive_account.this.id

  model {
    format  = "OpenAI"
    name    = each.value.model
    version = each.value.version
  }

  sku {
    name     = each.value.sku_name
    capacity = each.value.capacity
  }

  depends_on = [azurerm_cognitive_account_project.this]
}

module "private_endpoint" {
  source = "../private-endpoint"
  count  = var.private_networking ? 1 : 0

  name                = "pe-${var.name}"
  resource_group_name = var.private_endpoint_resource_group_name
  location            = var.location
  tags                = var.tags
  subnet_id           = var.private_endpoint_subnet_id
  target_resource_id  = azurerm_cognitive_account.this.id
  subresource_name    = "account"
  dns_zone_ids        = var.dns_zone_ids

  depends_on = [azurerm_cognitive_deployment.this]
}
