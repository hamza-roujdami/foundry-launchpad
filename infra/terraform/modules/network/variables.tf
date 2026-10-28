variable "resource_group_name" {
  description = "Resource group of the network."
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

variable "name" {
  description = "Name of the spoke VNet."
  type        = string
}

variable "address_space" {
  description = "Address space of the spoke VNet."
  type        = string
}

variable "network_role" {
  description = "Subnet profile: ai_hub (APIM) or ai_spokes (per-use-case ACA and shared Foundry)."
  type        = string
  validation {
    condition     = contains(["ai_hub", "ai_spokes"], var.network_role)
    error_message = "Use ai_hub or ai_spokes."
  }
}

variable "existing_dns_zone_ids" {
  description = "Non-null references a shared DNS authority; this module then creates no private DNS zones or links."
  type        = map(string)
  default     = null
}

variable "use_case_subnet_slots" {
  description = "Stable ACA /23 slot per use case in the AI spokes network."
  type        = map(number)
  default     = {}
}
