import { Tags, Backing, ZoneIds } from '../types.bicep'

@description('Use-case name.')
param name string
@description('Approved Azure region.')
param location string
@description('Ownership tags.')
param tags Tags
@description('Private endpoint subnet ID.')
param subnetId string
@description('Dedicated backing resources.')
param backing Backing
@description('Shared authoritative private DNS zone IDs.')
param zoneIds ZoneIds

var specs = [
  { name: 'blob', id: backing.storageId, groupId: 'blob' }
  { name: 'search', id: backing.searchId, groupId: 'searchService' }
  { name: 'cosmos', id: backing.cosmosId, groupId: 'Sql' }
  { name: 'keyvault', id: backing.vaultId, groupId: 'vault' }
]
module endpoints 'private-endpoint.bicep' = [
  for (spec, i) in specs: {
    name: 'endpoint-${name}-${i}'
    params: {
      name: 'pe-${spec.name}-${name}'
      location: location
      tags: tags
      subnetId: subnetId
      targetId: spec.id
      groupId: spec.groupId
      zoneIds: [zoneIds[spec.name]]
    }
  }
]
