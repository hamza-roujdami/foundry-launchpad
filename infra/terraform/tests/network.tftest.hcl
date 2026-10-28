mock_provider "azurerm" {}

run "hub_network_layout" {
  command = plan
  module {
    source = "./modules/network"
  }
  variables {
    name                = "test"
    resource_group_name = "test"
    location            = "centralus"
    tags                = {}
    address_space       = "10.20.0.0/16"
    network_role        = "ai_hub"
  }
  assert {
    condition = (
      one(azurerm_subnet.this["private-endpoints"].address_prefixes) == "10.20.0.0/26" &&
      one(azurerm_subnet.this["apim-outbound"].address_prefixes) == "10.20.0.64/27"
    )
    error_message = "Derived subnet ranges must be distinct and sufficiently sized for the supported services."
  }
  assert {
    condition     = length(azurerm_subnet_network_security_group_association.this) == 2 && azurerm_subnet.this["apim-outbound"].delegation[0].service_delegation[0].name == "Microsoft.Web/serverFarms"
    error_message = "Every subnet must have an NSG, with the APIM-specific delegation preserved."
  }
  assert {
    condition     = length(azurerm_private_dns_zone.this) == length(azurerm_private_dns_zone_virtual_network_link.this)
    error_message = "Each created private DNS zone must be linked to the local VNet."
  }
}

run "per_use_case_aca_subnets" {
  command = plan
  module {
    source = "./modules/network"
  }
  variables {
    name                  = "ai_spokes"
    resource_group_name   = "infra"
    location              = "centralus"
    tags                  = {}
    address_space         = "10.41.0.0/16"
    network_role          = "ai_spokes"
    existing_dns_zone_ids = {}
    use_case_subnet_slots = {
      ai-app-01 = 1
      ai-app-02 = 2
    }
  }
  assert {
    condition     = length(azurerm_subnet.this) == 4 && length(output.use_case_aca_subnet_ids) == 2 && length(azurerm_private_dns_zone.this) == 0
    error_message = "Spokes need one endpoint subnet, two ACA subnets and one shared Foundry subnet, without duplicating platform DNS."
  }
  assert {
    condition     = one(azurerm_subnet.this["aca-ai-app-01"].address_prefixes) == "10.41.2.0/23" && one(azurerm_subnet.this["aca-ai-app-02"].address_prefixes) == "10.41.4.0/23" && one(azurerm_subnet.this["foundry-agent"].address_prefixes) == "10.41.192.0/24"
    error_message = "ACA and Foundry runtime ranges must not overlap."
  }
}
