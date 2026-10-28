# Project guidelines: Foundry Launchpad

## What this repo is
A reference platform that gives AI engineers governed access to Microsoft Foundry through an API Management AI gateway. It is a workload deployed into an existing Azure landing zone. Platform and security controls must stay intact in every change.

## Reference sources (in order of precedence)
1. This README: the Launchpad architecture and resource-group ownership. Authoritative for this repo.
2. `Azure/terraform-azurerm-avm-ptn-aiml-landing-zone`: the AVM pattern module for the full AI/ML landing zone for Foundry. Follow its module layout, provider versions, and examples (`default`, `default-byo-vnet`, `standalone`, `standalone-byo-vnet`).
3. `Azure/terraform-ai-gateway-landing-zone`: the APIM AI gateway (Citadel). Use it for gateway policies, backend onboarding, model aliases, and access contracts.
4. `Azure/AI-Landing-Zones`: broader guidance. Not reviewed yet.

If these sources conflict with each other or with the README, flag the conflict and ask. Don't pick one silently.

## Architecture rules (do not violate)
- Models are reached only through the AI hub API Management gateway. Never add a direct call to a Foundry or Azure OpenAI endpoint from app code.
- Authentication: Entra ID tokens are the default. Use APIM subscription keys only when a consumer can't use Entra, and store them in Key Vault, never in code, tfvars, or chat.
- AI engineers never hold model keys.
- Each project gets its own managed identity, token limit, and usage tracking for showback.
- Private networking by default: private endpoints in the private endpoints subnet, with private DNS zones linked to the VNet.
- Resource-group owners: `rg-network` and `rg-ai-hub` belong to the platform team; `rg-ai-app` belongs to AI engineers. Don't move resources across that boundary without an explicit decision.
- Out of scope unless asked: platform landing zone, Entra tenant setup, Azure Policy, GitHub org setup, Application Gateway/WAF, knowledge sources, second region.

## Engineering approach
- Start with the simplest change that works. Ask when the request is ambiguous.
- Make surgical changes. Touch only what the task requires and match existing style.
- Define a verifiable success criterion before implementing: a `terraform plan` review, a validation script, a test, or a notebook check.
- Keep the README, `docs/`, and variable documentation in sync with any change to architecture, resource groups, subnets, or variables.

## Security
- Never commit secrets, keys, connection strings, subscription IDs, or tenant-specific values. Use `TF_VAR_` environment variables or Key Vault references.
- Don't weaken network rules, RBAC scopes, or gateway policies to make something work. Report the blocker instead.
- Least privilege for every role assignment. Scope it to the resource, not the subscription.

## Documentation lookups (MCP)
- For Microsoft Foundry and related services (Foundry, Azure OpenAI, API Management, AI Search, Cosmos DB, Key Vault, Container Apps, Content Safety, Event Hubs, Agent Framework), search Microsoft Learn (`microsoft_docs_search`) and fetch the relevant page (`microsoft_docs_fetch`) before writing configuration. Use `microsoft_code_sample_search` for official samples.
- Verify resource types, API versions, property names, SKUs, and regions against Learn. Don't guess.
- Use GitHub tools to read existing issues and PRs before proposing changes. Don't create, merge, or push unless asked.

## Diagrams
The architecture diagram is Mermaid in the README and an Obsidian canvas in `docs/reference-architecture.canvas`. Update both together when the architecture changes.