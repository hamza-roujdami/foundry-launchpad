import { Tags, Model, Monitoring } from '../types.bicep'

@description('Stable deployment suffix.')
param suffix string
@description('Approved Azure region.')
param location string
@description('Ownership tags.')
param tags Tags
@description('Real publisher email.')
param publisherEmail string
@description('Corporate tenant ID.')
param tenantId string
@description('Pre-provisioned gateway Entra application client ID.')
param gatewayClientId string
@description('Dedicated delegated APIM integration subnet.')
param apimSubnetId string
@description('Approved model deployment, not a reservation.')
param model Model
@description('Per-verified-caller token allowance.')
@minValue(1)
param tokensPerMinute int
@description('True only for first creation; set false for subsequent deployments to avoid reopening public access.')
param bootstrapPublicAccess bool

module monitoring 'monitoring.bicep' = {
  name: 'monitoring'
  params: { name: 'hub-${suffix}', location: location, tags: tags }
}
module foundry 'foundry.bicep' = {
  name: 'foundry'
  params: { name: 'foundry-hub-${suffix}', location: location, tags: tags, model: model }
}
resource insights 'Microsoft.Insights/components@2020-02-02' existing = { name: 'hub-${suffix}-appi' }
resource modelAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: 'foundry-hub-${suffix}'
}
resource safety 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: 'cs-hub-${suffix}'
  location: location
  tags: tags
  kind: 'ContentSafety'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: 'cs-hub-${suffix}'
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny' }
  }
}
resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: 'apim-ai-hub-${suffix}'
  location: location
  tags: tags
  sku: { name: 'StandardV2', capacity: 1 }
  identity: { type: 'SystemAssigned' }
  properties: {
    publisherName: 'Foundry Launchpad'
    publisherEmail: publisherEmail
    publicNetworkAccess: bootstrapPublicAccess ? 'Enabled' : 'Disabled'
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: { subnetResourceId: apimSubnetId }
  }
}
resource modelRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: modelAccount
  name: guid(modelAccount.id, apim.id, 'openai-user')
  properties: {
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    )
  }
  dependsOn: [foundry]
}
resource safetyRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: safety
  name: guid(safety.id, apim.id, 'cognitive-user')
  properties: {
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'a97b65f3-24c7-4388-baec-2e87135dc908'
    )
  }
}
resource backend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apim
  name: 'content-safety'
  properties: {
    description: 'Azure AI Content Safety'
    url: safety.properties.endpoint
    protocol: 'http'
    credentials: {
      // Supported by the REST backend contract, omitted by the bundled preview type catalog.
      #disable-next-line BCP037
      managedIdentity: { resource: 'https://cognitiveservices.azure.com' }
    }
  }
}
resource diagnostic 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: apim
  name: 'gateway-logs'
  properties: {
    workspaceId: monitoring.outputs.resources.workspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [{ category: 'GatewayLogs', enabled: true }]
  }
}
resource logger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'appinsights'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: monitoring.outputs.resources.appInsightsId
    credentials: { instrumentationKey: insights.properties.InstrumentationKey }
    isBuffered: true
  }
}
resource metrics 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerId: logger.id
    alwaysLog: 'allErrors'
    logClientIp: false
    verbosity: 'information'
    sampling: { samplingType: 'fixed', percentage: 100 }
    metrics: true
    frontend: { request: { body: { bytes: 0 } }, response: { body: { bytes: 0 } } }
    backend: { request: { body: { bytes: 0 } }, response: { body: { bytes: 0 } } }
  }
}

var backendUrl = '${foundry.outputs.endpoint}/openai'
resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'foundry'
  properties: {
    apiRevision: '1'
    displayName: 'Foundry'
    path: 'foundry'
    protocols: ['https']
    serviceUrl: backendUrl
    subscriptionRequired: false
  }
}
var operationSpecs = [
  { id: 'responses-create', name: 'Create a response', method: 'POST', path: '/v1/responses', responseId: false }
  { id: 'responses-get', name: 'Get a response', method: 'GET', path: '/v1/responses/{response_id}', responseId: true }
  {
    id: 'responses-delete'
    name: 'Delete a response'
    method: 'DELETE'
    path: '/v1/responses/{response_id}'
    responseId: true
  }
  {
    id: 'responses-cancel'
    name: 'Cancel a background response'
    method: 'POST'
    path: '/v1/responses/{response_id}/cancel'
    responseId: true
  }
  {
    id: 'responses-input-items'
    name: 'List input items'
    method: 'GET'
    path: '/v1/responses/{response_id}/input_items'
    responseId: true
  }
  {
    id: 'chat-completions-create'
    name: 'Create a chat completion'
    method: 'POST'
    path: '/v1/chat/completions'
    responseId: false
  }
]
resource operations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [
  for operation in operationSpecs: {
    parent: api
    name: operation.id
    properties: {
      displayName: operation.name
      method: operation.method
      urlTemplate: operation.path
      templateParameters: operation.responseId ? [{ name: 'response_id', required: true, type: 'string' }] : []
    }
    dependsOn: [policy]
  }
]
var policyTenant = replace(loadTextContent('../policies/gateway.xml'), '__TENANT_ID__', tenantId)
var policyClient = replace(policyTenant, '__CLIENT_ID__', gatewayClientId)
var policyBackend = replace(policyClient, '__BACKEND_URL__', backendUrl)
resource policy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  properties: { format: 'rawxml', value: replace(policyBackend, '__TOKENS_PER_MINUTE__', string(tokensPerMinute)) }
  dependsOn: [backend, metrics, modelRole, safetyRole]
}

output apimId string = apim.id
output apimName string = apim.name
output gatewayUrl string = '${apim.properties.gatewayUrl}/foundry/v1'
output foundryId string = foundry.outputs.id
output safetyId string = safety.id
output monitoring Monitoring = monitoring.outputs.resources
