variable "name" {
  description = "Account name. It is also the custom subdomain, so it must be globally unique."
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

variable "projects" {
  description = "Projects to create in the account."
  type        = set(string)
}

variable "deployments" {
  description = "Model deployments by name."
  type = map(object({
    model    = string
    version  = string
    sku_name = string
    capacity = number
  }))
  default = {}
}

variable "agent_subnet_id" {
  description = "Delegated subnet (Microsoft.App/environments) for hosted agents. It can only be set when the account is created; with it, the account is reachable only through its private endpoint. null creates no Agent Service network injection."
  type        = string
  default     = null
}

variable "private_networking" {
  description = "true closes the public endpoint and creates a private endpoint in private_endpoint_subnet_id."
  type        = bool
  default     = false
}

variable "private_endpoint_resource_group_name" {
  description = "Resource group that holds the private endpoints, the network resource group."
  type        = string
  default     = null
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the private endpoint."
  type        = string
  default     = null
}

variable "dns_zone_ids" {
  description = "Private DNS zones for the private endpoint."
  type        = list(string)
  default     = []
}
