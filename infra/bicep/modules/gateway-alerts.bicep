import { Tags } from '../types.bicep'

@description('Central gateway ARM resource ID.')
param gatewayId string
@description('Operational notification email.')
param email string
@description('Ownership tags.')
param tags Tags

resource operations 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-launchpad-operations'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'launchpad'
    enabled: true
    emailReceivers: [{ name: 'operations', emailAddress: email, useCommonAlertSchema: true }]
  }
}
var alertSpecs = [
  { name: 'errors', dimension: 'GatewayResponseCodeCategory', value: '5xx', threshold: 5, severity: 2 }
  { name: 'throttles', dimension: 'GatewayResponseCode', value: '429', threshold: 10, severity: 3 }
]
resource alerts 'Microsoft.Insights/metricAlerts@2018-03-01' = [
  for alert in alertSpecs: {
    name: 'alert-gateway-${alert.name}'
    location: 'global'
    tags: tags
    properties: {
      description: 'Gateway ${alert.name}: at least ${alert.threshold} responses in five minutes.'
      enabled: true
      severity: alert.severity
      scopes: [gatewayId]
      evaluationFrequency: 'PT1M'
      windowSize: 'PT5M'
      autoMitigate: true
      criteria: {
        'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
        allOf: [{
          name: alert.name
          criterionType: 'StaticThresholdCriterion'
          metricNamespace: 'Microsoft.ApiManagement/service'
          metricName: 'Requests'
          timeAggregation: 'Total'
          operator: 'GreaterThanOrEqual'
          threshold: alert.threshold
          dimensions: [{ name: alert.dimension, operator: 'Include', values: [alert.value] }]
        }]
      }
      actions: [{ actionGroupId: operations.id }]
    }
  }
]
