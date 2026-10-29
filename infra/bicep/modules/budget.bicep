@description('Approved monthly resource-group budget in billing currency; not a spending cap.')
@minValue(1)
param amount int
@description('First day of the deployment month, YYYY-MM-01T00:00:00Z. Keep stable on redeploy.')
param startDate string
@description('Operational notification email.')
param email string

resource budget 'Microsoft.Consumption/budgets@2024-08-01' = {
  name: 'budget-launchpad'
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: { startDate: startDate }
    notifications: {
      actual80: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: [email]
      }
      actual100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: [email]
      }
    }
  }
}
