output "vnet_id" {
  description = "Spoke VNet."
  value       = azurerm_virtual_network.this.id
}

output "private_endpoint_subnet_id" {
  description = "Subnet for private endpoints."
  value       = azurerm_subnet.this["private-endpoints"].id
}

output "apim_outbound_subnet_id" {
  description = "Subnet the gateway uses to reach private backends."
  value       = try(azurerm_subnet.this["apim-outbound"].id, null)
}

output "foundry_agent_subnet_id" {
  description = "Subnet for Foundry hosted agents."
  value       = try(azurerm_subnet.this["foundry-agent"].id, null)
}

output "dns_zone_ids" {
  description = "Private DNS zone IDs by short name."
  value       = var.existing_dns_zone_ids != null ? var.existing_dns_zone_ids : { for key, zone in azurerm_private_dns_zone.this : key => zone.id }
}

output "vnet_name" {
  description = "VNet name for explicitly managed cross-subscription peerings."
  value       = azurerm_virtual_network.this.name
}

output "use_case_aca_subnet_ids" {
  description = "Dedicated ACA subnets by use case, with stable address slots."
  value       = { for name in keys(var.use_case_subnet_slots) : name => azurerm_subnet.this["aca-${name}"].id }
}
