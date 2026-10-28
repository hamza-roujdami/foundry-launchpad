using './main.bicep'

param tenantId = readEnvironmentVariable('AZURE_TENANT_ID')
param hubSubscriptionId = readEnvironmentVariable('AZURE_AI_HUB_SUBSCRIPTION_ID')
param spokesSubscriptionId = readEnvironmentVariable('AZURE_AI_SPOKES_SUBSCRIPTION_ID')
param gatewayClientId = readEnvironmentVariable('GATEWAY_CLIENT_ID')
param gatewayServicePrincipalObjectId = readEnvironmentVariable('GATEWAY_SERVICE_PRINCIPAL_OBJECT_ID')
param gatewayAppRoleId = readEnvironmentVariable('GATEWAY_APP_ROLE_ID')
param publisherEmail = readEnvironmentVariable('APIM_PUBLISHER_EMAIL')
param location = 'centralus'
param regionCode = 'cus'
param bootstrapGatewayPublicAccess = true
param useCases = [
  { name: 'ai-app-01', subnetSlot: 1 }
  { name: 'ai-app-02', subnetSlot: 2 }
]
param model = {
  name: 'gpt-6-sol'
  version: '2026-09-22'
  skuName: 'DataZoneStandard'
  capacity: 15
}
