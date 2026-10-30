variable "tenant_id" {
  description = "Corporate Entra tenant shared by both subscriptions."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "Supply the Entra tenant UUID."
  }
}

variable "ai_hub_subscription_id" {
  description = "ID of sub-ai-hub-nonprod, containing shared AI networking, gateway and models. Providers use the ID, not its display name."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.ai_hub_subscription_id))
    error_message = "Supply the AI hub subscription UUID."
  }
}

variable "ai_spokes_subscription_id" {
  description = "ID of sub-ai-spokes-nonprod, containing the shared AI spokes foundation and use-case resources. Providers use the ID, not its display name."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.ai_spokes_subscription_id)) && lower(var.ai_spokes_subscription_id) != lower(var.ai_hub_subscription_id)
    error_message = "Supply a distinct AI spokes subscription UUID."
  }
}

variable "location" {
  description = "Approved region for both workload networks and services."
  type        = string
  default     = "centralus"
}

variable "region_code" {
  description = "Short region suffix used in resource group names."
  type        = string
  default     = "cus"
  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.region_code))
    error_message = "Use a 2-8 character lowercase region code."
  }
}

variable "deployment_name" {
  description = "Stable non-prod deployment name; changing it replaces named resources."
  type        = string
  default     = "foundry-launchpad-nonprod"
}

variable "use_cases" {
  description = "Use cases with projects in shared Foundry, dedicated ACA environments, backing services and RGs. No app or agent is deployed."
  type        = set(string)
  default     = ["ai-app-01", "ai-app-02"]
  validation {
    condition     = length(var.use_cases) > 0 && length(var.use_cases) <= 10 && alltrue([for name in var.use_cases : can(regex("^[a-z][a-z0-9-]{1,29}[a-z0-9]$", name)) && !strcontains(name, "--")])
    error_message = "Use 1-10 unique use-case names within the reference network capacity, each 3-31 lowercase letters/digits with single internal hyphens, starting with a letter."
  }
}

variable "tags" {
  description = "Tags applied to Launchpad-owned resources."
  type        = map(string)
  default     = { workload = "foundry-launchpad", environment = "nonprod" }
}

variable "publisher_email" {
  description = "Actual APIM publisher contact."
  type        = string
  validation {
    condition     = can(regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", var.publisher_email))
    error_message = "Supply a valid publisher contact email."
  }
}

variable "models" {
  description = "Three shared hub deployments keyed by fast-chat, advanced-chat and embeddings. Values pin actual model/version/SKU/capacity; capacity is allocation units, not a reservation."
  type = map(object({
    name     = string
    version  = string
    sku_name = string
    capacity = number
  }))
  default = {
    fast-chat     = { name = "gpt-6.1-sol", version = "2026-09-29", sku_name = "DataZoneStandard", capacity = 10 }
    advanced-chat = { name = "gpt-6.1-terra", version = "2026-10-26", sku_name = "DataZoneStandard", capacity = 10 }
    embeddings    = { name = "text-embedding-3-large", version = "1", sku_name = "DataZoneStandard", capacity = 10 }
  }
  validation {
    condition     = toset(keys(var.models)) == toset(["fast-chat", "advanced-chat", "embeddings"])
    error_message = "Supply exactly the three governed deployment aliases: fast-chat, advanced-chat and embeddings."
  }
  validation {
    condition     = alltrue([for model in values(var.models) : model.capacity > 0 && floor(model.capacity) == model.capacity])
    error_message = "Model capacity must be a positive integer matching regional model minimums."
  }
}

variable "embedding_requests_per_minute" {
  description = "Embedding requests per verified caller per minute; separate from chat token limits."
  type        = number
  default     = 60
  validation {
    condition     = var.embedding_requests_per_minute > 0 && floor(var.embedding_requests_per_minute) == var.embedding_requests_per_minute
    error_message = "Use a positive whole embedding request allowance."
  }
}

variable "tokens_per_minute" {
  description = "Token allowance per verified caller, not a reservation of backend capacity."
  type        = number
  default     = 10000
  validation {
    condition     = var.tokens_per_minute > 0 && floor(var.tokens_per_minute) == var.tokens_per_minute
    error_message = "Use a positive integer token allowance."
  }
}

variable "engineer_group_ids" {
  description = "Existing Entra groups granted project-level Foundry User access."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for id in var.engineer_group_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    error_message = "Use existing Entra group object UUIDs."
  }
}

variable "enable_agent_infrastructure" {
  description = "Provision private Standard Agent Service backing connections/capability hosts, but no agent definitions or containers."
  type        = bool
  default     = true
}

variable "ai_hub_address_space" {
  description = "AI hub IPv4 CIDR; must not overlap AI spokes or enterprise networks."
  type        = string
  default     = "10.40.0.0/16"
  validation {
    condition     = try(cidrnetmask(var.ai_hub_address_space) == "255.255.0.0", false)
    error_message = "New-network mode uses IPv4 /16 ranges for the supported subnet layout."
  }
}

variable "ai_spokes_address_space" {
  description = "AI spokes IPv4 CIDR; must not overlap AI hub or enterprise networks."
  type        = string
  default     = "10.41.0.0/16"
  validation {
    condition     = try(cidrnetmask(var.ai_spokes_address_space) == "255.255.0.0" && cidrhost(var.ai_spokes_address_space, 0) != cidrhost(var.ai_hub_address_space, 0), false)
    error_message = "Use a different IPv4 /16 for AI spokes; the new networks must not overlap."
  }
}

variable "existing_networks" {
  description = "Optional platform-owned VNet/subnet/DNS IDs. Existing DNS must resolve in both networks. Launchpad creates endpoints/records but does not manage existing VNets or zones. Configure routing externally; no peering is created in this mode."
  type = object({
    ai_hub = object({
      vnet_id                    = string
      private_endpoint_subnet_id = string
      apim_outbound_subnet_id    = string
      dns_zone_ids               = map(string)
    })
    ai_spokes = object({
      vnet_id                    = string
      private_endpoint_subnet_id = string
      use_case_aca_subnet_ids    = map(string)
      foundry_agent_subnet_id    = string
    })
  })
  default = null
  validation {
    condition = var.existing_networks == null ? true : alltrue([
      for key in ["apim", "cognitiveservices", "openai", "servicesai", "acr", "keyvault", "blob", "search", "cosmos", "monitor", "oms", "ods", "automation"] :
      contains(keys(var.existing_networks.ai_hub.dns_zone_ids), key)
    ])
    error_message = "Supply every private DNS zone key listed in the infrastructure guide."
  }
  validation {
    condition     = var.existing_networks == null ? true : alltrue([for name in var.use_cases : contains(keys(var.existing_networks.ai_spokes.use_case_aca_subnet_ids), name)])
    error_message = "Supply a dedicated ACA subnet for each use_case."
  }
}

variable "use_case_subnet_slots" {
  description = "Stable /23 subnet slot per use case within the AI spokes /16. Never renumber existing slots when adding a use case."
  type        = map(number)
  default     = { ai-app-01 = 1, ai-app-02 = 2 }
  validation {
    condition     = alltrue([for name in var.use_cases : contains(keys(var.use_case_subnet_slots), name)]) && length(distinct(values(var.use_case_subnet_slots))) == length(var.use_case_subnet_slots) && alltrue([for slot in values(var.use_case_subnet_slots) : slot >= 1 && slot <= 31 && floor(slot) == slot])
    error_message = "Every use case needs a unique integer subnet slot between 1 and 31."
  }
}
