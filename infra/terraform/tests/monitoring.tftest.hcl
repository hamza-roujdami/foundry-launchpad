mock_provider "azurerm" {}

run "private_telemetry" {
  command = plan
  module {
    source = "./modules/monitoring"
  }
  variables {
    name                = "test"
    resource_group_name = "test"
    location            = "swedencentral"
    tags                = {}
    private_networking  = true
  }
  assert {
    condition     = azurerm_log_analytics_workspace.this.internet_ingestion_access_type == "Disabled" && azurerm_log_analytics_workspace.this.internet_query_access_type == "Disabled"
    error_message = "Private monitoring must disable public workspace ingestion and query."
  }
  assert {
    condition     = !azurerm_application_insights.this.internet_ingestion_enabled && !azurerm_application_insights.this.internet_query_enabled
    error_message = "Private monitoring must disable public Application Insights ingestion and query."
  }
}
