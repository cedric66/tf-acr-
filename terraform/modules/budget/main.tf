resource "azurerm_consumption_budget_resource_group" "rg_budget" {
  name              = "budget-rg-10usd"
  resource_group_id = var.resource_group_id

  amount     = 10
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 90.0
    operator       = "EqualTo"
    threshold_type = "Actual"

    contact_emails = var.contact_emails
  }
}
