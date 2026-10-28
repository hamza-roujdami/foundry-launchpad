import { Tags } from '../types.bicep'

@description('Endpoint name.')
param name string
@description('Approved Azure region.')
param location string
@description('Ownership tags.')
param tags Tags
@description('Private-endpoint subnet resource ID.')
param subnetId string
@description('Target resource ID.')
param targetId string
@description('Private Link group ID.')
param groupId string
@description('Authoritative private DNS zone IDs.')
param zoneIds string[]

resource endpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetId }
    privateLinkServiceConnections: [
      {
        name: name
        properties: {
          privateLinkServiceId: targetId
          groupIds: [groupId]
        }
      }
    ]
  }
}
resource dns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: endpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      for (id, i) in zoneIds: {
        name: 'zone-${i}'
        properties: { privateDnsZoneId: id }
      }
    ]
  }
}

output id string = endpoint.id
output connectionState string = endpoint.properties.privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status
