import { Tags } from '../types.bicep'

@description('Gateway name.')
param name string
@description('Approved Azure region.')
param location string
@description('Ownership tags.')
param tags Tags
@description('Actual publisher contact.')
param publisherEmail string
@description('Dedicated delegated APIM subnet ID.')
param apimSubnetId string
@description('The endpoint must be approved; fail deployment rather than silently retain public access.')
param privateEndpointConnectionState string

// Separate ordered deployment: never declare the same APIM resource twice in one template.
resource gateway 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: { name: 'StandardV2', capacity: 1 }
  identity: { type: 'SystemAssigned' }
  properties: {
    publisherName: 'Foundry Launchpad'
    publisherEmail: publisherEmail
    // Unknown, pending or rejected connections fail the deployment with an out-of-range index.
    publicNetworkAccess: ['Disabled'][indexOf(['Approved'], privateEndpointConnectionState)]
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: { subnetResourceId: apimSubnetId }
  }
}

output publicNetworkAccess string = gateway.properties.publicNetworkAccess
output endpointState string = privateEndpointConnectionState
