variable "name" {
  description = "Prefix of the Log Analytics workspace and Application Insights names."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group."
  type        = string
}

variable "location" {
  description = "Region."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}

variable "private_networking" {
  description = "Disable public telemetry ingestion/query. The root attaches these resources to AMPLS."
  type        = bool
  default     = false
}
