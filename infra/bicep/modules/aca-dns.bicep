import { Tags } from '../types.bicep'

@description('ACA environment default domain.')
param domain string
@description('Internal load-balancer private address.')
param ip string
@description('ACA subnet parent VNet ID.')
param vnetId string
@description('Ownership tags.')
param tags Tags

resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: domain
  location: 'global'
  tags: tags
}
resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: 'aca-network'
  location: 'global'
  tags: tags
  properties: { registrationEnabled: false, virtualNetwork: { id: vnetId } }
}
resource records 'Microsoft.Network/privateDnsZones/A@2024-06-01' = [
  for name in ['@', '*']: {
    parent: zone
    name: name
    properties: { ttl: 300, aRecords: [{ ipv4Address: ip }] }
  }
]
