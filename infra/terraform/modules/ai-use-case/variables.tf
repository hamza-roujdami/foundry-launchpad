variable "resource_group_name" {
  description = "Application-owned resource group containing the use case services and ACA environment."
  type        = string
}

variable "location" {
  description = "Azure region for the use_case."
  type        = string
}

variable "tags" {
  description = "Tags applied to use case resources."
  type        = map(string)
}

variable "name_suffix" {
  description = "Stable, globally unique six-character lowercase alphanumeric suffix supplied by the caller."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{6}$", var.name_suffix))
    error_message = "Use exactly six lowercase alphanumeric characters."
  }
}

variable "tenant_id" {
  description = "Entra tenant ID used by Key Vault."
  type        = string
}

variable "use_case_name" {
  description = "Use-case name used for the application blob container, Cosmos database and resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}[a-z0-9]$", var.use_case_name)) && !strcontains(var.use_case_name, "--")
    error_message = "Use 3-31 lowercase letters, digits or single hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "registry" {
  description = "Existing private foundation registry; no registry or images are created by this module."
  type = object({
    id           = string
    name         = string
    login_server = string
  })
}

variable "foundry" {
  description = "Existing foundation Foundry account and use case project, including its system-assigned identity and endpoint."
  type = object({
    id                   = string
    project_id           = string
    project_principal_id = string
    project_endpoint     = string
  })
}

variable "private_endpoint_resource_group_name" {
  description = "AI spokes network resource group owning private endpoints and environment DNS."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "AI spokes private-endpoint subnet shared by the use case backing services."
  type        = string
}

variable "aca_subnet_id" {
  description = "Dedicated delegated ACA subnet in the AI spokes VNet; its VNet receives the environment DNS link."
  type        = string
}

variable "dns_zone_ids" {
  description = "Existing private DNS zone IDs keyed by blob, search, cosmos and keyvault."
  type        = map(string)

  validation {
    condition     = alltrue([for key in ["blob", "search", "cosmos", "keyvault"] : contains(keys(var.dns_zone_ids), key)])
    error_message = "Provide blob, search, cosmos and keyvault private DNS zone IDs."
  }
}

variable "engineer_group_ids" {
  description = "Entra groups granted Foundry User only on this use case's existing project."
  type        = set(string)
  default     = []
}

variable "enable_agent_infrastructure" {
  description = "Create the three BYO service connections, project service roles and Agent Service capability host; never deploy an agent."
  type        = bool
  default     = true
}
