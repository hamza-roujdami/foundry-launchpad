import { Tags, Monitoring } from '../types.bicep'

@description('Stable deployment suffix.')
param suffix string
@description('Approved Azure region.')
param location string
@description('Ownership tags.')
param tags Tags
@description('Delegated Agent Service subnet; empty to omit agent networking.')
param agentSubnetId string

module foundry 'foundry.bicep' = {
  name: 'foundry'
  params: { name: 'foundry-spokes-${suffix}', location: location, tags: tags, agentSubnetId: agentSubnetId }
}
module monitoring 'monitoring.bicep' = {
  name: 'monitoring'
  params: { name: 'spokes-${suffix}', location: location, tags: tags }
}
resource registry 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: 'acrlaunchpad${suffix}'
  location: location
  tags: tags
  sku: { name: 'Premium' }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    policies: { azureADAuthenticationAsArmPolicy: { status: 'enabled' } }
  }
}

output foundryId string = foundry.outputs.id
output foundryName string = foundry.outputs.name
output registryId string = registry.id
output registryName string = registry.name
output registryLoginServer string = registry.properties.loginServer
output monitoring Monitoring = monitoring.outputs.resources
