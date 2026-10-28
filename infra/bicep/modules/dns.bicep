import { Tags, ZoneIds } from '../types.bicep'

@description('Hub and spokes virtual network IDs.')
param vnetIds string[]
@description('Ownership tags.')
param tags Tags

var zoneNames = {
  apim: 'privatelink.azure-api.net'
  cognitiveservices: 'privatelink.cognitiveservices.azure.com'
  openai: 'privatelink.openai.azure.com'
  servicesai: 'privatelink.services.ai.azure.com'
  search: 'privatelink.search.windows.net'
  cosmos: 'privatelink.documents.azure.com'
  blob: 'privatelink.blob.${environment().suffixes.storage}'
  acr: 'privatelink.azurecr.io'
  keyvault: 'privatelink.vaultcore.azure.net'
  monitor: 'privatelink.monitor.azure.com'
  oms: 'privatelink.oms.opinsights.azure.com'
  ods: 'privatelink.ods.opinsights.azure.com'
  automation: 'privatelink.agentsvc.azure-automation.net'
}

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in items(zoneNames): {
    name: zone.value
    location: 'global'
    tags: tags
  }
]

module links 'dns-links.bicep' = [
  for (zone, i) in items(zoneNames): {
    name: 'links-${zone.key}'
    params: { zoneName: zones[i].name, vnetIds: vnetIds, tags: tags }
  }
]

output ids ZoneIds = toObject(
  items(zoneNames),
  zone => zone.key,
  zone => resourceId('Microsoft.Network/privateDnsZones', zone.value)
)
