---
applyTo: "**/*.tf,**/*.tfvars.example"
description: "Terraform changes: preserve the Launchpad architecture, pinned providers, private access and scoped identity contracts."
---

# Terraform rules

## Module layout
- Keep the single root in `infra/terraform/`, split by concern with `main.<area>.tf`. Reuse existing focused modules, not wrapper layers.
- Follow the README's five resource-group boundaries; shared infrastructure stays outside app-owned groups.
- Use typed inputs and stable caller-provided map keys, never keys unknown at plan time.
- Preserve new-network and `existing_networks` modes. The root supplies shared Foundry/project and registry references to use cases; no standalone account variants.
- `resource_group_name` must not already exist unless it is imported into state first.

## Versions
- Preserve `versions.tf` and `.terraform.lock.hcl`: Terraform `~> 1.12`, AzureRM `~> 5.11`, AzAPI `~> 2.13` and AzureAD `~> 3.10`.
- Do not add unused providers or overwrite these constraints with upstream pins.
- Don't bump a provider major version without a written plan.

## Identity and access
- Use managed identities for service-to-service calls.
- Grant the gateway's managed identity the OpenAI User role on Foundry, scoped to the account.
- Each project identity gets the gateway role. No one gets model keys.
- Disable local authentication using the pinned provider's properties: `local_auth_enabled = false` for Foundry, `local_authentication_disabled = true` for Cosmos DB and `shared_access_key_enabled = false` for Storage.
- Qualify connection names with the use-case name; capability-host bindings require reviewed replacement if those names change.

## Networking
- Give every service that supports a private endpoint one in the private endpoints subnet.
- Preserve disabled public access with the resource-specific properties supported by the pinned provider.
- Standard v2 APIM uses `"External"` for outbound VNet integration plus inbound Private Link, not classic internal injection. Preserve ordered public-access closure after endpoint approval.
- Keep the 10-use-case bound for the reference `/26` endpoint subnet. Review private IP capacity and both IaC implementations before increasing it.
- Private DNS zones belong to the network resource group and are linked to the VNet. Other groups reference them by ID.

## Gateway (APIM)
- Route all model traffic through APIM.
- Keep policy XML in versioned policy files, not inline strings.
- Enforce the shared three-alias model/operation allowlist. Do not claim independent model entitlements per project.
- Keep caller-based inference token limits and metrics. Response lifecycle operations must remain available when inference allowance is exhausted.
- Embeddings use a separate request limit and usage metric, not unsupported chat-token policies.

## Secrets and state
- Never put secrets in `.tfvars`. Use `TF_VAR_` environment variables or Key Vault.
- Commit only `*.tfvars.example`. Confirm `.gitignore` excludes real `*.tfvars` and state files.
- Platform engineers supply a protected remote backend. This repo does not create backend storage or include a bootstrap script; never commit real backend settings or state.

## Before merging
- Run `terraform -chdir=infra/terraform fmt -check -recursive`, `validate` and `test`, plus relevant Python tests.
- Review a real plan against an approved target with required inputs/backend; never apply Terraform over Bicep-owned resources.
- Run verification and explicitly approved synthetic smoke tests from private connectivity. Separate offline evidence from live behavior.
- Update the variables documentation when a variable changes.
- Keep provider registration disabled in Terraform; platform operators register providers through their approved process.