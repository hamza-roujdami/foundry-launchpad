import { Tags, UseCase, Project } from '../types.bicep'

@description('Shared Foundry account name.')
param accountName string
@description('Project definitions.')
param useCases UseCase[]
@description('Approved Azure region.')
param location string
@description('Ownership tags.')
param tags Tags

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = { name: accountName }
@batchSize(1)
resource projects 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = [
  for app in useCases: {
    parent: account
    name: app.name
    location: location
    tags: tags
    identity: { type: 'SystemAssigned' }
    properties: { displayName: app.name }
  }
]

output projects Project[] = [
  for (app, i) in useCases: {
    name: app.name
    id: projects[i].id
    principalId: projects[i].identity.principalId
    endpoint: 'https://${accountName}.services.ai.azure.com/api/projects/${app.name}'
  }
]
