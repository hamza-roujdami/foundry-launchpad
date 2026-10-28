import { Backing, Monitoring } from '../types.bicep'

@description('Shared Foundry account name.')
param accountName string
@description('Project name.')
param projectName string
@description('Shared ACR name.')
param registryName string
@description('Runtime managed identity object ID.')
param runtimePrincipalId string
@description('Existing engineer Entra group object IDs.')
param engineerGroupIds string[]
@description('Create BYO service connections and project capability host.')
param enableAgents bool
@description('Dedicated application backing services.')
param backing Backing
@description('Dedicated application monitoring.')
param monitoring Monitoring
@description('Approved Azure region.')
param location string

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = { name: accountName }
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: account
  name: projectName
}
resource registry 'Microsoft.ContainerRegistry/registries@2025-04-01' existing = { name: registryName }
resource insights 'Microsoft.Insights/components@2020-02-02' existing = {
  scope: resourceGroup(split(monitoring.appInsightsId, '/')[2], split(monitoring.appInsightsId, '/')[4])
  name: last(split(monitoring.appInsightsId, '/'))
}
resource runtimeProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: project
  name: guid(project.id, runtimePrincipalId, 'foundry-user')
  properties: {
    principalId: runtimePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '53ca6127-db72-4b80-b1b0-d745d6d5456d'
    )
  }
}
resource engineers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for id in engineerGroupIds: {
    scope: project
    name: guid(project.id, id, 'foundry-user')
    properties: {
      principalId: id
      principalType: 'Group'
      roleDefinitionId: subscriptionResourceId(
        'Microsoft.Authorization/roleDefinitions',
        '53ca6127-db72-4b80-b1b0-d745d6d5456d'
      )
    }
  }
]
resource pull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: registry
  name: guid(registry.id, runtimePrincipalId, 'pull')
  properties: {
    principalId: runtimePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    )
  }
}
resource tracing 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: project
  name: 'appinsights'
  properties: {
    category: 'AppInsights'
    target: monitoring.appInsightsId
    authType: 'ApiKey'
    isSharedToAll: false
    credentials: { key: insights.properties.ConnectionString }
    metadata: { ApiType: 'Azure', ResourceId: monitoring.appInsightsId }
  }
}

var connectionSpecs = [
  { name: 'agent-files', category: 'AzureStorageAccount', target: backing.storageEndpoint, id: backing.storageId }
  { name: 'agent-search', category: 'CognitiveSearch', target: backing.searchEndpoint, id: backing.searchId }
  { name: 'agent-threads', category: 'CosmosDb', target: backing.cosmosEndpoint, id: backing.cosmosId }
]
@batchSize(1)
resource connections 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = [
  for connection in connectionSpecs: if (enableAgents) {
    parent: project
    name: connection.name
    properties: {
      category: connection.category
      target: connection.target
      authType: 'AAD'
      metadata: { ApiType: 'Azure', ResourceId: connection.id, location: location }
    }
    dependsOn: [tracing]
  }
]
resource capabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = if (enableAgents) {
  parent: project
  name: 'agents'
  properties: {
    // The Standard Agent Service REST contract requires this field; the bundled preview schema omits it.
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    storageConnections: ['agent-files']
    threadStorageConnections: ['agent-threads']
    vectorStoreConnections: ['agent-search']
  }
  dependsOn: [connections]
}
