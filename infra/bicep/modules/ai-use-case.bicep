import { Tags, Backing, Monitoring } from '../types.bicep'

@description('Use-case name.')
param name string
@description('Stable globally unique suffix.')
param suffix string
@description('Approved Azure region.')
param location string
@description('Corporate tenant ID.')
param tenantId string
@description('Ownership tags.')
param tags Tags
@description('Dedicated delegated ACA subnet resource ID.')
param acaSubnetId string
@description('Foundry project managed identity object ID.')
param projectPrincipalId string
@description('Create Standard Agent Service permissions.')
param enableAgents bool

module monitoring 'monitoring.bicep' = {
  name: 'monitoring'
  params: { name: '${name}-${suffix}', location: location, tags: tags }
}
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = { name: '${name}-${suffix}-law' }
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${name}'
  location: location
  tags: tags
}
resource environment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: 'cae-${name}-${suffix}'
  location: location
  tags: tags
  properties: {
    publicNetworkAccess: 'Disabled'
    vnetConfiguration: { infrastructureSubnetId: acaSubnetId, internal: true }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [{ name: 'Consumption', workloadProfileType: 'Consumption' }]
  }
  dependsOn: [monitoring]
}
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'stlp${suffix}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'None' }
  }
}
resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: { enabled: true, days: 7 }
    containerDeleteRetentionPolicy: { enabled: true, days: 7 }
  }
}
resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blob
  name: name
  properties: { publicAccess: 'None' }
}
resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: 'search-${name}-${suffix}'
  location: location
  tags: tags
  sku: { name: 'basic' }
  properties: {
    replicaCount: 1
    partitionCount: 1
    disableLocalAuth: true
    publicNetworkAccess: 'disabled'
  }
}
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: 'cosmos-${name}-${suffix}'
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    minimalTlsVersion: 'Tls12'
    capabilities: [{ name: 'EnableServerless' }]
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [{ locationName: location, failoverPriority: 0, isZoneRedundant: false }]
  }
}
resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: cosmos
  name: name
  properties: { resource: { id: name } }
}
resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${suffix}'
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'None' }
  }
}

resource runtimeBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: container
  name: guid(container.id, identity.id, 'blob-contributor')
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
  }
}
resource runtimeSearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: search
  name: guid(search.id, identity.id, 'search-data')
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
    )
  }
}
resource runtimeVault 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vault
  name: guid(vault.id, identity.id, 'vault-secrets')
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'
    )
  }
}
resource runtimeCosmos 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: cosmos
  name: guid(cosmos.id, identity.id, name)
  properties: {
    principalId: identity.properties.principalId
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: '${cosmos.id}/dbs/${database.name}'
  }
}
resource agentBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableAgents) {
  scope: storage
  name: guid(storage.id, projectPrincipalId, 'blob-owner')
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
    )
  }
}
resource agentSearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableAgents) {
  scope: search
  name: guid(search.id, projectPrincipalId, 'search-service')
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
    )
  }
}
resource agentSearchData 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableAgents) {
  scope: search
  name: guid(search.id, projectPrincipalId, 'search-data')
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
    )
  }
}
resource agentCosmosOperator 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableAgents) {
  scope: cosmos
  name: guid(cosmos.id, projectPrincipalId, 'cosmos-operator')
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '230815da-be43-4aae-9cb4-875f7bd000aa'
    )
  }
}
resource agentCosmosData 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = if (enableAgents) {
  parent: cosmos
  name: guid(cosmos.id, projectPrincipalId, 'agents')
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmos.id
  }
}

output identityId string = identity.id
output identityPrincipalId string = identity.properties.principalId
output identityClientId string = identity.properties.clientId
output environmentId string = environment.id
output environmentDomain string = environment.properties.defaultDomain
output environmentIp string = environment.properties.staticIp
output monitoring Monitoring = monitoring.outputs.resources
output backing Backing = {
  storageId: storage.id
  storageEndpoint: storage.properties.primaryEndpoints.blob
  searchId: search.id
  searchEndpoint: 'https://${search.name}.search.windows.net'
  cosmosId: cosmos.id
  cosmosEndpoint: cosmos.properties.documentEndpoint
  vaultId: vault.id
}
