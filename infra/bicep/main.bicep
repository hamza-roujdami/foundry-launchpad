targetScope = 'subscription'

import { Tags, Models, UseCase, ExistingNetworks, Project, RuntimeIdentity, ApplicationBacking, NamedResource, Operations } from './types.bicep'

@description('Corporate Entra tenant shared by both subscriptions.')
@minLength(36)
@maxLength(36)
param tenantId string
@description('Existing hub subscription ID. Run the root deployment in this subscription.')
@minLength(36)
@maxLength(36)
param hubSubscriptionId string
@description('Distinct existing spokes subscription ID in the same tenant.')
@minLength(36)
@maxLength(36)
param spokesSubscriptionId string
@description('Existing single-tenant gateway Entra application client ID; see bootstrap instructions.')
@minLength(36)
@maxLength(36)
param gatewayClientId string
@description('Existing gateway enterprise application object ID; required for operator-run app-role assignments.')
@minLength(36)
@maxLength(36)
param gatewayServicePrincipalObjectId string
@description('Existing Gateway.Invoke app-role UUID; value must be Gateway.Invoke and allowedMemberTypes Application.')
@minLength(36)
@maxLength(36)
param gatewayAppRoleId string
@description('Actual APIM publisher contact email.')
param publisherEmail string
@description('Approved operational contact, first day of deployment month and monthly resource-group budgets.')
param operations Operations
@description('Approved region. Model availability must be checked, never inferred.')
param location string = 'centralus'
@description('Short region suffix in resource-group names.')
param regionCode string = 'cus'
@description('Stable non-production deployment name.')
param deploymentName string = 'foundry-launchpad-nonprod'
@description('Ownership tags.')
param tags Tags = { workload: 'foundry-launchpad', environment: 'nonprod' }
@description('Use cases with unique stable /23 subnet slots, 1-31. Do not renumber existing slots.')
@minLength(1)
@maxLength(16)
param useCases UseCase[] = [{ name: 'ai-app-01', subnetSlot: 1 }, { name: 'ai-app-02', subnetSlot: 2 }]
@description('Approved model name/version/SKU/capacity; deployment can fail if region or quota is unavailable.')
param models Models = {
  'fast-chat': { name: 'gpt-6.1-sol', version: '2026-09-29', skuName: 'DataZoneStandard', capacity: 10 }
  'advanced-chat': { name: 'gpt-6.1-terra', version: '2026-10-26', skuName: 'DataZoneStandard', capacity: 10 }
  embeddings: { name: 'text-embedding-3-large', version: '1', skuName: 'DataZoneStandard', capacity: 10 }
}
@description('Per-verified-caller token allowance, not backend reserved capacity.')
@minValue(1)
param tokensPerMinute int = 10000
@description('Embedding requests per verified caller per minute, separate from chat token limits.')
@minValue(1)
param embeddingRequestsPerMinute int = 60
@description('Existing engineer Entra group object IDs granted project-scoped Foundry User.')
param engineerGroupIds string[] = []
@description('Provision network injection, BYO service connections and project capability hosts; no agents.')
param enableAgentInfrastructure bool = true
@description('Non-overlapping hub /16 IPv4 range for new-network mode.')
param hubAddressPrefix string = '10.40.0.0/16'
@description('Non-overlapping spokes /16 IPv4 range for new-network mode.')
param spokesAddressPrefix string = '10.41.0.0/16'
@description('Existing network references; externally managed routing, delegations, NSGs and DNS links are prerequisites.')
param existingNetworks ExistingNetworks?
@description('True ONLY for first APIM creation. Set false on subsequent deployments to prevent reopening gateway access.')
param bootstrapGatewayPublicAccess bool = true

var suffix = take(uniqueString(tenantId, deploymentName), 6)
var hubInfra = 'rg-ai-hub-infra-nonprod-${regionCode}'
var hubServices = 'rg-ai-hub-services-nonprod-${regionCode}'
var spokesInfra = 'rg-ai-spokes-infra-nonprod-${regionCode}'
var appGroupNames = [for app in useCases: 'rg-${app.name}-dev-${regionCode}']

module hubGroups 'modules/resource-groups.bicep' = {
  name: 'hub-groups'
  scope: subscription(hubSubscriptionId)
  params: { names: [hubInfra, hubServices], location: location, tags: tags }
}
module spokesGroups 'modules/resource-groups.bicep' = {
  name: 'spokes-groups'
  scope: subscription(spokesSubscriptionId)
  params: {
    names: concat([spokesInfra], appGroupNames)
    location: location
    tags: tags
    groupTags: toObject(useCases, app => 'rg-${app.name}-dev-${regionCode}', app => { use_case: app.name })
  }
}
module hubNetwork 'modules/network.bicep' = if (existingNetworks == null) {
  name: 'hub-network'
  scope: resourceGroup(hubSubscriptionId, hubInfra)
  params: {
    name: 'vnet-ai-hub-nonprod-${regionCode}-${suffix}'
    location: location
    tags: tags
    addressPrefix: hubAddressPrefix
    role: 'hub'
    useCases: useCases
  }
  dependsOn: [hubGroups]
}
module spokesNetwork 'modules/network.bicep' = if (existingNetworks == null) {
  name: 'spokes-network'
  scope: resourceGroup(spokesSubscriptionId, spokesInfra)
  params: {
    name: 'vnet-ai-spokes-nonprod-${regionCode}-${suffix}'
    location: location
    tags: tags
    addressPrefix: spokesAddressPrefix
    role: 'spokes'
    useCases: useCases
  }
  dependsOn: [spokesGroups]
}
var hubVnetId = existingNetworks == null ? hubNetwork!.outputs.id : existingNetworks!.hub.vnetId
var spokesVnetId = existingNetworks == null ? spokesNetwork!.outputs.id : existingNetworks!.spokes.vnetId
var hubPeSubnet = existingNetworks == null
  ? hubNetwork!.outputs.privateEndpointSubnetId
  : existingNetworks!.hub.privateEndpointSubnetId
var spokesPeSubnet = existingNetworks == null
  ? spokesNetwork!.outputs.privateEndpointSubnetId
  : existingNetworks!.spokes.privateEndpointSubnetId
var apimSubnet = existingNetworks == null ? hubNetwork!.outputs.apimSubnetId : existingNetworks!.hub.apimSubnetId
var agentSubnet = existingNetworks == null
  ? spokesNetwork!.outputs.agentSubnetId
  : existingNetworks!.spokes.agentSubnetId
var acaSubnets = existingNetworks == null ? spokesNetwork!.outputs.acaSubnetIds : existingNetworks!.spokes.acaSubnetIds

module hubPeering 'modules/peering.bicep' = if (existingNetworks == null) {
  name: 'hub-peering'
  scope: resourceGroup(hubSubscriptionId, hubInfra)
  params: { name: 'to-ai-spokes', vnetName: hubNetwork!.outputs.name, remoteVnetId: spokesVnetId }
}
module spokesPeering 'modules/peering.bicep' = if (existingNetworks == null) {
  name: 'spokes-peering'
  scope: resourceGroup(spokesSubscriptionId, spokesInfra)
  params: { name: 'to-ai-hub', vnetName: spokesNetwork!.outputs.name, remoteVnetId: hubVnetId }
}
module dns 'modules/dns.bicep' = if (existingNetworks == null) {
  name: 'private-dns'
  scope: resourceGroup(hubSubscriptionId, hubInfra)
  params: { vnetIds: [hubVnetId, spokesVnetId], tags: tags }
}
var zones = existingNetworks == null ? dns!.outputs.ids : existingNetworks!.hub.dnsZoneIds
var foundryZoneIds = [zones.cognitiveservices, zones.openai, zones.servicesai]

module hub 'modules/ai-hub-services.bicep' = {
  name: 'hub-services'
  scope: resourceGroup(hubSubscriptionId, hubServices)
  params: {
    suffix: suffix
    location: location
    tags: tags
    publisherEmail: publisherEmail
    tenantId: tenantId
    gatewayClientId: gatewayClientId
    apimSubnetId: apimSubnet
    models: models
    embeddingRequestsPerMinute: embeddingRequestsPerMinute
    tokensPerMinute: tokensPerMinute
    bootstrapPublicAccess: bootstrapGatewayPublicAccess
  }
  dependsOn: [hubGroups]
}
var hubEndpointSpecs = [
  { name: 'foundry', id: hub.outputs.foundryId, groupId: 'account', zones: foundryZoneIds }
  { name: 'safety', id: hub.outputs.safetyId, groupId: 'account', zones: [zones.cognitiveservices] }
]
module hubEndpoints 'modules/private-endpoint.bicep' = [
  for i in range(0, 2): {
    name: 'hub-endpoint-${i}'
    scope: resourceGroup(hubSubscriptionId, hubInfra)
    params: {
      name: 'pe-hub-${hubEndpointSpecs[i].name}-${suffix}'
      location: location
      tags: tags
      subnetId: hubPeSubnet
      targetId: hubEndpointSpecs[i].id
      groupId: hubEndpointSpecs[i].groupId
      zoneIds: hubEndpointSpecs[i].zones
    }
    dependsOn: [hubGroups]
  }
]
module gatewayEndpoint 'modules/private-endpoint.bicep' = {
  name: 'gateway-endpoint'
  scope: resourceGroup(hubSubscriptionId, hubInfra)
  params: {
    name: 'pe-apim-${suffix}'
    location: location
    tags: tags
    subnetId: hubPeSubnet
    targetId: hub.outputs.apimId
    groupId: 'Gateway'
    zoneIds: [zones.apim]
  }
  dependsOn: [hubGroups]
}
module gatewayClosure 'modules/gateway-private-access.bicep' = {
  name: 'gateway-private-closure'
  scope: resourceGroup(hubSubscriptionId, hubServices)
  params: {
    name: hub.outputs.apimName
    location: location
    tags: tags
    publisherEmail: publisherEmail
    apimSubnetId: apimSubnet
    privateEndpointConnectionState: gatewayEndpoint.outputs.connectionState
  }
}

module spokes 'modules/ai-spokes-services.bicep' = {
  name: 'spokes-services'
  scope: resourceGroup(spokesSubscriptionId, spokesInfra)
  params: {
    suffix: suffix
    location: location
    tags: tags
    agentSubnetId: enableAgentInfrastructure ? agentSubnet : ''
  }
  dependsOn: [spokesGroups]
}
module projects 'modules/projects.bicep' = {
  name: 'projects'
  scope: resourceGroup(spokesSubscriptionId, spokesInfra)
  params: { accountName: spokes.outputs.foundryName, useCases: useCases, location: location, tags: tags }
}
var spokesEndpointSpecs = [
  { name: 'foundry', id: spokes.outputs.foundryId, groupId: 'account', zones: foundryZoneIds }
  { name: 'acr', id: spokes.outputs.registryId, groupId: 'registry', zones: [zones.acr] }
]
module spokesEndpoints 'modules/private-endpoint.bicep' = [
  for i in range(0, 2): {
    name: 'spokes-endpoint-${i}'
    scope: resourceGroup(spokesSubscriptionId, spokesInfra)
    params: {
      name: 'pe-spokes-${spokesEndpointSpecs[i].name}-${suffix}'
      location: location
      tags: tags
      subnetId: spokesPeSubnet
      targetId: spokesEndpointSpecs[i].id
      groupId: spokesEndpointSpecs[i].groupId
      zoneIds: spokesEndpointSpecs[i].zones
    }
    dependsOn: [projects]
  }
]

module applications 'modules/ai-use-case.bicep' = [
  for (app, i) in useCases: {
    name: 'application-${app.name}'
    scope: resourceGroup(spokesSubscriptionId, 'rg-${app.name}-dev-${regionCode}')
    params: {
      name: app.name
      suffix: take(uniqueString(suffix, app.name), 6)
      location: location
      tenantId: tenantId
      tags: union(tags, { use_case: app.name })
      acaSubnetId: acaSubnets[app.name]
      projectPrincipalId: projects.outputs.projects[i].principalId
      enableAgents: enableAgentInfrastructure
    }
    dependsOn: [spokesGroups]
  }
]
module backingEndpoints 'modules/backing-endpoints.bicep' = [
  for (app, i) in useCases: {
    name: 'backing-endpoints-${app.name}'
    scope: resourceGroup(spokesSubscriptionId, spokesInfra)
    params: {
      name: '${app.name}-${suffix}'
      location: location
      tags: tags
      subnetId: spokesPeSubnet
      backing: applications[i].outputs.backing
      zoneIds: zones
    }
  }
]
module acaDns 'modules/aca-dns.bicep' = [
  for (app, i) in useCases: {
    name: 'aca-dns-${app.name}'
    scope: resourceGroup(spokesSubscriptionId, spokesInfra)
    params: {
      domain: applications[i].outputs.environmentDomain
      ip: applications[i].outputs.environmentIp
      vnetId: split(acaSubnets[app.name], '/subnets/')[0]
      tags: tags
    }
  }
]
@batchSize(1)
module projectBindings 'modules/project-bindings.bicep' = [
  for (app, i) in useCases: {
    name: 'project-bindings-${app.name}'
    scope: resourceGroup(spokesSubscriptionId, spokesInfra)
    params: {
      accountName: spokes.outputs.foundryName
      projectName: app.name
      registryName: spokes.outputs.registryName
      runtimePrincipalId: applications[i].outputs.identityPrincipalId
      engineerGroupIds: engineerGroupIds
      enableAgents: enableAgentInfrastructure
      backing: applications[i].outputs.backing
      monitoring: applications[i].outputs.monitoring
      location: location
      gatewayUrl: hub.outputs.gatewayUrl
      gatewayAudience: 'api://${gatewayClientId}'
      models: models
    }
    dependsOn: [backingEndpoints, spokesEndpoints, hubPeering, spokesPeering, gatewayClosure]
  }
]
module privateMonitoring 'modules/private-monitoring.bicep' = {
  name: 'private-monitoring'
  scope: resourceGroup(hubSubscriptionId, hubInfra)
  params: {
    name: 'ampls-${suffix}'
    location: location
    tags: tags
    subnetId: hubPeSubnet
    zoneIds: zones
    sharedMonitoring: [hub.outputs.monitoring, spokes.outputs.monitoring]
    applicationMonitoring: [for (app, i) in useCases: applications[i].outputs.monitoring]
  }
}

module gatewayAlerts 'modules/gateway-alerts.bicep' = {
  name: 'gateway-alerts'
  scope: resourceGroup(hubSubscriptionId, hubServices)
  params: { gatewayId: hub.outputs.apimId, email: operations.email, tags: tags }
}
var appBudgetSpecs = [for app in useCases: {
  subscriptionId: spokesSubscriptionId
  group: 'rg-${app.name}-dev-${regionCode}'
  amount: operations.monthlyBudgets.perApp
}]
var budgetSpecs = concat([
  { subscriptionId: hubSubscriptionId, group: hubInfra, amount: operations.monthlyBudgets.hubInfra }
  { subscriptionId: hubSubscriptionId, group: hubServices, amount: operations.monthlyBudgets.hubServices }
  { subscriptionId: spokesSubscriptionId, group: spokesInfra, amount: operations.monthlyBudgets.spokesInfra }
], appBudgetSpecs)
module budgets 'modules/budget.bicep' = [
  for budget in budgetSpecs: {
    name: 'budget-${budget.group}'
    scope: resourceGroup(budget.subscriptionId, budget.group)
    params: { amount: budget.amount, startDate: operations.budgetStartDate, email: operations.email }
    dependsOn: [hubGroups, spokesGroups]
  }
]

@description('Non-secret input for infra/scripts/smoke.py. Live inference is a separate explicit operator step.')
output readiness array = [for (app, i) in useCases: {
  name: app.name
  project_id: projects.outputs.projects[i].id
  project_endpoint: projects.outputs.projects[i].endpoint
  private_urls: [
    applications[i].outputs.backing.storageEndpoint
    applications[i].outputs.backing.searchEndpoint
    applications[i].outputs.backing.cosmosEndpoint
    'https://${last(split(applications[i].outputs.backing.vaultId, '/'))}${environment().suffixes.keyvaultDns}'
  ]
  gateway_url: hub.outputs.gatewayUrl
  gateway_audience: 'api://${gatewayClientId}'
  gateway_id: hub.outputs.apimId
  connection_name: 'ai-gateway'
  model: 'fast-chat'
  agent_model: 'ai-gateway/fast-chat'
  agents_enabled: enableAgentInfrastructure
  registry_url: 'https://${spokes.outputs.registryLoginServer}'
}]

@description('OpenAI v1-compatible APIM endpoint; never call the Foundry model endpoint directly.')
output gatewayUrl string = hub.outputs.gatewayUrl
output gatewayPublicNetworkAccess string = gatewayClosure.outputs.publicNetworkAccess
output projects Project[] = projects.outputs.projects
output runtimeIdentities RuntimeIdentity[] = [
  for (app, i) in useCases: {
    name: app.name
    id: applications[i].outputs.identityId
    principalId: applications[i].outputs.identityPrincipalId
    clientId: applications[i].outputs.identityClientId
  }
]
output backingServices ApplicationBacking[] = [
  for (app, i) in useCases: { name: app.name, services: applications[i].outputs.backing }
]
output registry { id: string, loginServer: string } = {
  id: spokes.outputs.registryId
  loginServer: spokes.outputs.registryLoginServer
}
output containerAppEnvironmentIds NamedResource[] = [
  for (app, i) in useCases: { name: app.name, id: applications[i].outputs.environmentId }
]
@description('Operator must grant Gateway.Invoke to runtimeIdentities and listed project principals using scripts/gateway-identity.py assign.')
output gatewayAuthorization {
  clientId: string
  servicePrincipalObjectId: string
  appRoleId: string
  roleValue: string
  projectPrincipalIds: string[]
} = {
  clientId: gatewayClientId
  servicePrincipalObjectId: gatewayServicePrincipalObjectId
  appRoleId: gatewayAppRoleId
  roleValue: 'Gateway.Invoke'
  projectPrincipalIds: enableAgentInfrastructure ? map(projects.outputs.projects, project => project.principalId) : []
}
