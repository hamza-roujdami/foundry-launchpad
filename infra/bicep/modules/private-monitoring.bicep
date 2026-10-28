import { Tags, ZoneIds, Monitoring } from '../types.bicep'

@description('AMPLS name.')
param name string
@description('Approved Azure region for private endpoint.')
param location string
@description('Ownership tags.')
param tags Tags
@description('Private endpoint subnet ID.')
param subnetId string
@description('Shared private DNS zone IDs.')
param zoneIds ZoneIds
@description('Hub and spokes workspace and Application Insights resources.')
param sharedMonitoring Monitoring[]
@description('Per-application workspace and Application Insights resources.')
param applicationMonitoring Monitoring[]

resource scope 'Microsoft.Insights/privateLinkScopes@2021-07-01-preview' = {
  name: name
  location: 'global'
  tags: tags
  properties: { accessModeSettings: { ingestionAccessMode: 'PrivateOnly', queryAccessMode: 'PrivateOnly' } }
}
var monitoring = concat(sharedMonitoring, applicationMonitoring)
var monitoringPairs = [for service in monitoring: [service.workspaceId, service.appInsightsId]]
var resourceIds = flatten(monitoringPairs)
resource services 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = [
  for (id, i) in resourceIds: {
    parent: scope
    name: 'monitoring-${i}'
    properties: { linkedResourceId: id }
  }
]
module endpoint 'private-endpoint.bicep' = {
  name: 'endpoint'
  params: {
    name: 'pe-${name}'
    location: location
    tags: tags
    subnetId: subnetId
    targetId: scope.id
    groupId: 'azuremonitor'
    zoneIds: [zoneIds.monitor, zoneIds.oms, zoneIds.ods, zoneIds.automation, zoneIds.blob]
  }
  dependsOn: [services]
}
