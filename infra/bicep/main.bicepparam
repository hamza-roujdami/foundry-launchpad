using './main.bicep'

param tenantId = readEnvironmentVariable('AZURE_TENANT_ID')
param hubSubscriptionId = readEnvironmentVariable('AZURE_AI_HUB_SUBSCRIPTION_ID')
param spokesSubscriptionId = readEnvironmentVariable('AZURE_AI_SPOKES_SUBSCRIPTION_ID')
param gatewayClientId = readEnvironmentVariable('GATEWAY_CLIENT_ID')
param gatewayServicePrincipalObjectId = readEnvironmentVariable('GATEWAY_SERVICE_PRINCIPAL_OBJECT_ID')
param gatewayAppRoleId = readEnvironmentVariable('GATEWAY_APP_ROLE_ID')
param publisherEmail = readEnvironmentVariable('APIM_PUBLISHER_EMAIL')
param operations = {
  email: readEnvironmentVariable('OPERATIONS_EMAIL')
  budgetStartDate: readEnvironmentVariable('BUDGET_START_DATE')
  monthlyBudgets: {
    hubInfra: int(readEnvironmentVariable('BUDGET_HUB_INFRA'))
    hubServices: int(readEnvironmentVariable('BUDGET_HUB_SERVICES'))
    spokesInfra: int(readEnvironmentVariable('BUDGET_SPOKES_INFRA'))
    perApp: int(readEnvironmentVariable('BUDGET_PER_APP'))
  }
}
param location = 'centralus'
param regionCode = 'cus'
param bootstrapGatewayPublicAccess = true
param useCases = [
  { name: 'ai-app-01', subnetSlot: 1 }
  { name: 'ai-app-02', subnetSlot: 2 }
]
param models = {
  'fast-chat': { name: 'gpt-6.1-sol', version: '2026-09-29', skuName: 'DataZoneStandard', capacity: 10 }
  'advanced-chat': { name: 'gpt-6.1-terra', version: '2026-10-26', skuName: 'DataZoneStandard', capacity: 10 }
  embeddings: { name: 'text-embedding-3-large', version: '1', skuName: 'DataZoneStandard', capacity: 10 }
}
param embeddingRequestsPerMinute = 60
