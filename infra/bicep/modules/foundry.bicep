import { Tags, Models } from '../types.bicep'

@description('Foundry account name.')
param name string
@description('Approved Azure region; no automatic model-driven relocation.')
param location string
@description('Ownership tags.')
param tags Tags
@description('Agent subnet resource ID, empty for model-only hub.')
param agentSubnetId string = ''
@description('Optional approved model deployment.')
param models Models?

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: name
    allowProjectManagement: true
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny' }
    networkInjections: empty(agentSubnetId)
      ? []
      : [
          {
            scenario: 'agent'
            subnetArmId: agentSubnetId
            useMicrosoftManagedNetwork: false
          }
        ]
  }
}

@batchSize(1)
resource deployments 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = [
  for entry in items(models ?? {}): {
    parent: account
    name: entry.key
    sku: { name: entry.value.skuName, capacity: entry.value.capacity }
    properties: {
      model: { format: 'OpenAI', name: entry.value.name, version: entry.value.version }
    }
  }
]

output id string = account.id
output name string = account.name
output endpoint string = account.properties.endpoint
