resource "azurerm_log_analytics_workspace" "this" {
  name                           = "${var.name}-law"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  sku                            = "PerGB2018"
  retention_in_days              = 30
  internet_ingestion_access_type = var.private_networking ? "Disabled" : "Enabled"
  internet_query_access_type     = var.private_networking ? "Disabled" : "Enabled"
  tags                           = var.tags
}

resource "azurerm_application_insights" "this" {
  name                       = "${var.name}-appi"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  workspace_id               = azurerm_log_analytics_workspace.this.id
  application_type           = "web"
  internet_ingestion_enabled = !var.private_networking
  internet_query_enabled     = !var.private_networking
  tags                       = var.tags
}
