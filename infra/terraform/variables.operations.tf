variable "operations" {
  description = "Approved notification contact and monthly RG budgets in billing currency. Budgets alert only; they do not stop spending. Start date must be the first day of the deployment month."
  type = object({
    email             = string
    budget_start_date = string
    monthly_budgets = object({
      hub_infra    = number
      hub_services = number
      spokes_infra = number
      per_app      = number
    })
  })

  validation {
    condition     = can(regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", var.operations.email))
    error_message = "Supply an operational notification email."
  }
  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-01T00:00:00Z$", var.operations.budget_start_date)) && can(timeadd(var.operations.budget_start_date, "0h"))
    error_message = "Supply the first day of the deployment month as YYYY-MM-01T00:00:00Z."
  }
  validation {
    condition     = alltrue([for amount in values(var.operations.monthly_budgets) : amount > 0 && floor(amount) == amount])
    error_message = "Every monthly resource-group budget must be a positive whole amount in billing currency."
  }
}
