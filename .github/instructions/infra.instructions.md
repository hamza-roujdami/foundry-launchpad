---
applyTo: "**/*.tf,**/*.tfvars.example"
---

# Terraform rules

## Module layout
- Follow the AVM layout: split by concern into `main.<area>.tf`, `variables.<area>.tf`, `outputs.<area>.tf`, and `locals.<area>.tf` (for example networking, foundry, apim, monitoring, genai_services).
- Keep resource groups separate by owner (network, AI hub, agent landing zone).
- Use the AVM variable style: optional attributes with defaults, and maps keyed by arbitrary names. Don't use map keys that depend on values unknown at plan time.
- Support both new and existing resources through `existing_resource_id` or BYO variables. Reuse an existing VNet, DNS zones, or Foundry account instead of duplicating it.
- `resource_group_name` must not already exist unless it is imported into state first.

## Versions
- Terraform `>= 1.9, < 2.0`, azurerm `~> 4.0`, azapi `~> 2.12`, plus modtm, random, and time.
- Don't bump a provider major version without a written plan.

## Identity and access
- Use managed identities for service-to-service calls.
- Grant the gateway's managed identity the OpenAI User role on Foundry, scoped to the account.
- Each project identity gets the gateway role. No one gets model keys.
- Disable local authentication where the platform allows it: `disable_local_auth = true` for Foundry, `local_authentication_disabled = true` for Cosmos DB, and `shared_access_key_enabled = false` for storage.

## Networking
- Give every service that supports a private endpoint one in the private endpoints subnet.
- Set `public_network_access_enabled = false` for AI services and Cosmos DB unless the README says otherwise.
- For production APIM, use `virtual_network_type = "Internal"` as the gateway reference does. Use `"External"` only with a documented reason.
- Private DNS zones belong to the network resource group and are linked to the VNet. Other groups reference them by ID.

## Gateway (APIM)
- Route all model traffic through APIM.
- Keep policy XML in versioned policy files, not inline strings.
- Model aliases and per-project access contracts follow the Citadel pattern.
- Set a token limit and usage metric for each project.

## Secrets and state
- Never put secrets in `.tfvars`. Use `TF_VAR_` environment variables or Key Vault.
- Commit only `*.tfvars.example`. Confirm `.gitignore` excludes real `*.tfvars` and state files.
- Use the remote state backend from the bootstrap script. Don't commit local state.

## Before merging
- Run `terraform fmt`, `terraform validate`, and `terraform plan`. Review the plan for RBAC, network, and public-access changes.
- Run the repo's validate script or smoke tests against the deployment.
- Update the variables documentation when a variable changes.
- Use the provider settings from the AVM examples in policy-restricted tenants.