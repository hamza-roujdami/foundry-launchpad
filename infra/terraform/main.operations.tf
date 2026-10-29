resource "azurerm_monitor_action_group" "operations" {
  name                = "ag-launchpad-operations"
  resource_group_name = azurerm_resource_group.ai_hub["services"].name
  short_name          = "launchpad"
  tags                = var.tags

  email_receiver {
    name                    = "operations"
    email_address           = var.operations.email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_metric_alert" "gateway" {
  for_each = {
    errors    = { dimension = "GatewayResponseCodeCategory", value = "5xx", threshold = 5, severity = 2 }
    throttles = { dimension = "GatewayResponseCode", value = "429", threshold = 10, severity = 3 }
  }

  name                = "alert-gateway-${each.key}"
  resource_group_name = azurerm_resource_group.ai_hub["services"].name
  scopes              = [module.ai_hub_services.apim_id]
  description         = "Gateway ${each.key}: at least ${each.value.threshold} responses in five minutes."
  severity            = each.value.severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.ApiManagement/service"
    metric_name      = "Requests"
    aggregation      = "Total"
    operator         = "GreaterThanOrEqual"
    threshold        = each.value.threshold
    dimension {
      name     = each.value.dimension
      operator = "Include"
      values   = [each.value.value]
    }
  }
  action {
    action_group_id = azurerm_monitor_action_group.operations.id
  }
}

resource "azurerm_consumption_budget_resource_group" "hub" {
  for_each = {
    network  = var.operations.monthly_budgets.hub_infra
    services = var.operations.monthly_budgets.hub_services
  }
  name              = "budget-launchpad"
  resource_group_id = azurerm_resource_group.ai_hub[each.key].id
  amount            = each.value
  time_grain        = "Monthly"
  time_period {
    start_date = var.operations.budget_start_date
  }
  dynamic "notification" {
    for_each = toset([80, 100])
    content {
      enabled        = true
      threshold      = notification.value
      threshold_type = "Actual"
      operator       = "GreaterThanOrEqualTo"
      contact_emails = [var.operations.email]
    }
  }
}

resource "azurerm_consumption_budget_resource_group" "spokes" {
  provider = azurerm.ai_spokes
  for_each = merge(
    { infrastructure = { id = azurerm_resource_group.ai_spokes["network"].id, amount = var.operations.monthly_budgets.spokes_infra } },
    { for name, group in azurerm_resource_group.ai_use_case : "app-${name}" => { id = group.id, amount = var.operations.monthly_budgets.per_app } }
  )
  name              = "budget-launchpad"
  resource_group_id = each.value.id
  amount            = each.value.amount
  time_grain        = "Monthly"
  time_period {
    start_date = var.operations.budget_start_date
  }
  dynamic "notification" {
    for_each = toset([80, 100])
    content {
      enabled        = true
      threshold      = notification.value
      threshold_type = "Actual"
      operator       = "GreaterThanOrEqualTo"
      contact_emails = [var.operations.email]
    }
  }
}
