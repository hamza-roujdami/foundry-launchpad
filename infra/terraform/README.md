# Terraform infrastructure

One Terraform root, two existing subscriptions in one Entra tenant, five resource
groups. Infrastructure only: no apps, jobs, images, agent definitions or inference.
See the [architecture and cost estimate](../../README.md).

## Ownership

| Subscription | Resource group | Contents |
|---|---|---|
| `sub-ai-hub-nonprod` | `rg-ai-hub-infra-nonprod-cus` | Hub VNet, subnets, NSGs, private endpoints, shared DNS and AMPLS |
| `sub-ai-hub-nonprod` | `rg-ai-hub-services-nonprod-cus` | APIM Standard v2, model Foundry, Content Safety, gateway identity and monitoring |
| `sub-ai-spokes-nonprod` | `rg-ai-spokes-infra-nonprod-cus` | Spokes network, subnets, endpoints, ACR Premium, shared Foundry with two projects and runtime monitoring |
| `sub-ai-spokes-nonprod` | `rg-ai-app-01-dev-cus` | Internal ACA environment, runtime identity, private Storage/Search/Cosmos/Key Vault and telemetry |
| `sub-ai-spokes-nonprod` | `rg-ai-app-02-dev-cus` | The same dedicated use-case resources |

Azure also creates managed infrastructure groups for ACA; they are owned by the
environments, not additional user-managed foundations. Foundry projects stay
under their shared account, while their backing services live in the app groups.

## Code layout

```text
infra/terraform/
  main.tf                       # Resource groups and shared naming/network references
  main.ai-hub.tf                # Hub network and AI hub services
  main.ai-spokes.tf             # Spokes network, shared Foundry, ACR and monitoring
  main.ai-use-cases.tf          # One AI use-case module per use case
  main.connectivity.tf          # Cross-subscription peering and DNS links
  main.identity.tf              # Gateway Entra application and caller roles
  main.private-monitoring.tf    # Shared private monitoring access
  main.operations.tf           # RG budgets and gateway alerts
  providers.tf                 # Root-only provider configuration
  versions.tf                  # Terraform and provider constraints
  variables.tf                 # Typed, validated root inputs
  variables.operations.tf      # Required budget/contact inputs
  outputs.tf                   # Consumer outputs and verification contract
  modules/
    ai-hub-services/            # APIM, model hosting, Content Safety and telemetry
    ai-use-case/                # Dedicated ACA, identity, backing services and connections
    network/                   # Reusable hub/spokes network profiles
    foundry/                   # Reusable account, projects and model deployments
    monitoring/                # Reusable private logs and traces
    private-endpoint/          # Reusable endpoint and DNS zone group
  tests/                       # Credential-free Terraform plan tests
```

Folder names use hyphens; Terraform identifiers use underscores, for example
`module.ai_hub_services`, `module.ai_spokes_foundry` and
`module.ai_use_case["ai-app-01"]`. The root shows subscription placement;
modules group cohesive capabilities, not one wrapper per resource group.
Shared Foundry, registry and subnet references are passed into each use case.
Small monitoring/endpoint helpers are reused rather than copied.

This follows HashiCorp's [standard module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure),
[style guide](https://developer.hashicorp.com/terraform/language/style) and
[module composition guidance](https://developer.hashicorp.com/terraform/language/modules/develop/composition):
typed inputs and described outputs, explicit dependencies, root provider
configuration, shallow composition and consistent formatting. Module READMEs
explain purpose and boundaries; provider constraints and the lockfile are retained.
The `ai-*` vocabulary is our architecture convention, not a HashiCorp requirement.

## Inputs

Start from [terraform.tfvars.example](terraform.tfvars.example). Real values
belong only in ignored local configuration or `TF_VAR_` environment variables.

| Input | Meaning |
|---|---|
| `tenant_id` | Existing tenant shared by both subscriptions |
| `ai_hub_subscription_id` | ID of the AI hub subscription |
| `ai_spokes_subscription_id` | ID of the AI spokes subscription; must differ |
| `location`, `region_code` | Approved region and short naming suffix; defaults `centralus`, `cus` |
| `deployment_name` | Stable naming seed; changing it replaces named resources |
| `publisher_email` | Real APIM contact |
| `operations` | Required operational email, initial budget start date and four monthly amounts: hub_infra, hub_services, spokes_infra, per_app |
| `use_cases` | Use-case names; defaults ai-app-01 and ai-app-02 |
| `use_case_subnet_slots` | Unique, stable /23 slots; defaults 1 and 2. Never renumber existing slots |
| `engineer_group_ids` | Existing Entra groups for project-scoped Foundry User access |
| `enable_agent_infrastructure` | Private BYO connections/capability hosts, not agent definitions |
| `models` | Exactly fast-chat, advanced-chat and embeddings, each with actual model name, version, SKU and capacity; no PTU reservation |
| `tokens_per_minute` | Per-caller gateway allowance, not backend quota |
| `embedding_requests_per_minute` | Separate per-caller embedding request limit; default 60, not a token cap |
| `ai_hub_address_space`, `ai_spokes_address_space` | Distinct IPv4 /16 ranges |
| `existing_networks` | Optional existing VNet/subnet/DNS references instead of creating networks |
| `tags` | Resource tags |

Resource names use a stable six-character hash of tenant/deployment/use case.
Human-readable prefixes identify their role. No customer IDs are embedded in
publishable files.

## Networking and identity

New-network mode creates bilateral VNet peering. Private DNS is owned once in the
hub and linked to both networks. Each ACA environment has its own internal zone.
The default spokes layout is endpoints `10.41.0.0/26`, ACA `10.41.2.0/23` and
`10.41.4.0/23`, and shared Foundry runtime `10.41.192.0/24`.

APIM has inbound Private Link and outbound delegated VNet integration in its own
subscription/region. It briefly permits public access during creation; an ordered
update closes access after its endpoint is approved. Services use Entra, not
model/storage keys. Runtime identities and project identities are separate.
Roles are scoped to projects, resources or application namespaces.

`existing_networks` requires VNet IDs, private-endpoint subnet IDs, the APIM
outbound subnet, one ACA subnet per use case, the shared Foundry subnet and DNS
keys `apim`, `cognitiveservices`, `openai`, `servicesai`, `acr`, `keyvault`,
`blob`, `search`, `cosmos`, `monitor`, `oms`, `ods`, `automation`.
Its top-level keys are `ai_hub` and `ai_spokes`; the latter includes
`use_case_aca_subnet_ids` keyed by use-case name.
In this mode, supply working routing, delegation, DNS links and permissions.
Terraform does not manage existing VNets, shared zones, links or peerings.
Existing platform firewalls and routing remain platform-owned.
Coordinate AMPLS/DNS with the platform owner. Reusing an existing ACR, monitoring
workspace or AMPLS is not implemented.

With agent infrastructure enabled, every project gets an `ai-gateway`
`ApiManagement` connection to the hub's `/foundry/v1` endpoint. It uses
`ProjectManagedIdentity`, the custom gateway audience, and a serialized static
approved chat-model list. Agents select `ai-gateway/fast-chat` or
`ai-gateway/advanced-chat`; embeddings are called by application/indexing code
through APIM, not offered as an agent chat model. Alias names are the actual hub
deployment names; APIM rejects other aliases and mismatched operations.
The preview connection uses the official sample contract with AzAPI schema
validation disabled only for that resource because the embedded schema omits
this authentication type. No model key or second APIM is created.
Runtime assets and [live acceptance checks](../README.md#private-access-and-agent-smoke-test)
remain separate. Private endpoints do not guarantee egress isolation or residency.

Use the three-model catalog in [the root README](../../README.md#model-access-pattern).
This replaces the previous singular `model` input: update ignored local inputs
to `models` rather than keeping an unused legacy value. A deployment that already
has model resources must review the replacement/deletion plan before applying;
alias deployments do not automatically adopt old deployment names.

## Validate and deploy

Requirements: Terraform matching [versions.tf](versions.tf), Azure CLI, Python 3,
resource/RBAC permissions in both subscriptions and Entra application permissions.
An authorized operator must register Network, Web, ApiManagement,
CognitiveServices, Insights, OperationalInsights and ManagedIdentity in the hub;
Network, App, CognitiveServices, ContainerRegistry, Storage, Search, DocumentDB,
KeyVault, Insights, OperationalInsights, ManagedIdentity, ContainerService and
MachineLearningServices in spokes. Register Consumption in both subscriptions
for resource-group budgets. Check regional availability and actual quota;
an advertised offering is not an allocation guarantee.

```bash
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
# Fill local inputs. Configure a team-approved remote state backend before team use.
terraform -chdir=infra/terraform init -lockfile=readonly
terraform -chdir=infra/terraform workspace new launchpad-nonprod
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform test
terraform -chdir=infra/terraform plan -out=tfplan
# Review target subscriptions, private access, resource-scoped roles and cost.
terraform -chdir=infra/terraform apply tfplan
bash infra/terraform/test.sh
terraform -chdir=infra/terraform plan -detailed-exitcode
```

Select the same workspace on subsequent runs. Never reuse another tenant's state,
discard state to hide a resource or apply new code over an old deployment without
review. State and saved plans are sensitive and must stay out of Git.

`test.sh` calls the read-only `verify.sh`: tenant/subscriptions, groups, private
access, endpoint count/approval, peering, DNS links, AMPLS, private telemetry,
all three model deployments and project capability hosts. It never reads keys or invokes
models. Failures are nonzero. DNS checks target only the supplied zone IDs,
including zones in different resource groups or subscriptions. New-network mode
checks bilateral peering and links to both VNets. Existing-network mode explicitly
skips customer-managed routing/DNS-link topology; validate those paths from an
authorized private runner.

These are control-plane checks, not packet-flow tests. Registry pulls, private
DNS, authenticated gateway requests and actual log delivery require an authorized
private runner and separately approved runtime tests. Export the `readiness`
output for the shared [preflight and synthetic agent smoke test](../README.md#private-access-and-agent-smoke-test).

Budgets use `operations.budget_start_date`, the first day of the initial deployment
month, retained on later applies. Every RG has 80%/100% notifications. Gateway
alerts and the action group live in hub services. See the shared
[operations guide](../README.md#basic-operational-controls) for thresholds and
cost coverage limitations.

The verifier's offline regression tests use only the Python standard library:

```bash
python3 -m unittest discover -s infra/terraform/tests -p 'test_*.py'
```

## Lifecycle

Review resource replacements and data retention before applying a plan.
Preserve state for reconciliation and regenerate saved plans after configuration
changes. Soft-deleted resource names may remain reserved; never purge accounts
or vaults as an automatic fix.

Delete capability hosts/projects before accounts and backing services; wait for
ACA and its managed groups before deleting their subnets. Confirm actual Azure
absence, not just a successful CLI wait or state removal. Unrelated governance,
alerts, Network Watcher and other subscriptions are outside Launchpad's scope.
