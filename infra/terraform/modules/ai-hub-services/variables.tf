variable "resource_group_name" {
  description = "Resource group of the AI hub."
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

variable "name_suffix" {
  description = "Short unique suffix used in resource names."
  type        = string
}

variable "publisher_email" {
  description = "Contact email of the API Management instance."
  type        = string
}

variable "apim_sku_name" {
  description = "API Management v2 tier and capacity."
  type        = string
}

variable "gateway_public_access" {
  description = "false closes the public gateway endpoint."
  type        = bool
}

variable "tokens_per_minute" {
  description = "Token limit per caller per minute. 0 turns the limit off."
  type        = number
}

variable "model" {
  description = "The model to deploy."
  type = object({
    name     = string
    version  = string
    sku_name = string
    capacity = number
  })
}

variable "deploy_content_safety" {
  description = "Check prompts with Azure AI Content Safety."
  type        = bool
}

variable "tenant_id" {
  description = "Tenant that issues the caller tokens."
  type        = string
}

variable "gateway_client_id" {
  description = "Client ID of the gateway app registration, the audience of the tokens."
  type        = string
}

variable "gateway_role" {
  description = "App role a caller token must carry."
  type        = string
}

variable "private_networking" {
  description = "true creates private endpoints, closes the public endpoints of Foundry and Content Safety, and integrates the gateway with the VNet."
  type        = bool
}

variable "private_endpoint_resource_group_name" {
  description = "Resource group that holds the private endpoints, the network resource group."
  type        = string
  default     = null
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for private endpoints."
  type        = string
  default     = null
}

variable "apim_outbound_subnet_id" {
  description = "Delegated subnet (Microsoft.Web/serverFarms) the gateway uses to reach private backends."
  type        = string
  default     = null
}

variable "dns_zone_ids" {
  description = "Private DNS zone IDs by short name."
  type        = map(string)
  default     = {}
  nullable    = false
}
