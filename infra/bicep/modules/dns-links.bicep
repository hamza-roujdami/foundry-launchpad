import { Tags } from '../types.bicep'

@description('Private DNS zone name.')
param zoneName string
@description('VNets that share this DNS authority.')
param vnetIds string[]
@description('Ownership tags.')
param tags Tags

resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = { name: zoneName }
resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (id, i) in vnetIds: {
    parent: zone
    name: 'network-${i}'
    location: 'global'
    tags: tags
    properties: { registrationEnabled: false, virtualNetwork: { id: id } }
  }
]
