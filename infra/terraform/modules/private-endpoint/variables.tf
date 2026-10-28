variable "name" {
  description = "Name of the private endpoint."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the private endpoint."
  type        = string
}

variable "location" {
  description = "Region."
  type        = string
}

variable "tags" {
  description = "Tags applied to the private endpoint."
  type        = map(string)
}

variable "subnet_id" {
  description = "Subnet for the private endpoint."
  type        = string
}

variable "target_resource_id" {
  description = "Resource to reach privately."
  type        = string
}

variable "subresource_name" {
  description = "Sub-resource of the target, for example account, registry, vault or Gateway."
  type        = string
}

variable "dns_zone_ids" {
  description = "Private DNS zones to register the endpoint in."
  type        = list(string)
}
