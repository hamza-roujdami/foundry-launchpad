# Foundry Launchpad

## Executive summary

AI engineers need to test ideas quickly. Setting up model access, networking,
identity and data services should not take longer than building a prototype.
Repeating that setup for every use case slows teams down and leaves platform
engineers supporting inconsistent environments.

Foundry Launchpad provides a non-production Azure foundation for AI development.
The platform team owns shared model access and network controls. Engineers get a
workspace with Foundry, data services and infrastructure for future apps and agents.

This phase deploys infrastructure only. It does not deploy apps, agent
definitions, container images or public endpoints for end users.

## What it provisions

Two existing subscriptions in one corporate Entra tenant, in Central US:

- **ai-hub: shared model access and governance.** Hosts the models and the
  central **APIM AI gateway**, including API operations, policies and gateway
  monitoring. The platform team owns the ai-hub.
- **ai-spoke: development workspaces and application infrastructure.** Hosts
  the shared Foundry account and registry, plus a project, internal ACA
  environment and backing services for each use case. Engineers own the app
  resource groups; shared infrastructure stays outside those groups.

The model path is **ai-spoke project or application -> ai-hub APIM -> ai-hub model**.
The ai-app-01 and ai-app-02 applications themselves are not deployed.

### With the default two-app configuration

| Subscription | Resource group | What you get |
|---|---|---|
| `sub-ai-hub-nonprod` | `rg-ai-hub-infra-nonprod-cus` | ai-hub VNet, APIM/private-endpoint subnets, NSGs, private endpoints, shared private DNS and Azure Monitor Private Link Scope |
| `sub-ai-hub-nonprod` | `rg-ai-hub-services-nonprod-cus` | APIM Standard v2, private Foundry model account with three alias deployments, Content Safety, monitoring, gateway alerts and email action group |
| `sub-ai-spokes-nonprod` | `rg-ai-spokes-infra-nonprod-cus` | ai-spoke VNet, peering, dedicated ACA subnets, shared Agent Service subnet, private endpoints, shared ACR Premium, one shared Foundry account with two projects and shared monitoring |
| `sub-ai-spokes-nonprod` | `rg-ai-app-01-dev-cus` | Dedicated internal ACA environment, runtime identity, Storage Standard LRS, AI Search Basic, Cosmos DB serverless, Key Vault Standard and monitoring |
| `sub-ai-spokes-nonprod` | `rg-ai-app-02-dev-cus` | A separate set of the same dedicated application infrastructure |

### Connections and controls included

| Where | Capability | What is configured |
|---|---|---|
| **ai-hub / APIM** | API operations | Chat completions, embeddings and five Responses operations: create, get, delete, cancel and list input items |
| **ai-hub / APIM** | Authentication and model access | Entra token and `Gateway.Invoke` role validation; three-alias model/operation allowlist; managed identity to the model backend, not model keys |
| **ai-hub / APIM** | Usage and safety policies | Chat token limits, prompt safety/Prompt Shield, caller-owned Responses, retries on 429/503; separate embedding request limits |
| **ai-hub** | Gateway operations and monitoring | Caller/model usage metrics, embedding token metrics, gateway logs, and email alerts for 5xx errors and 429 throttling |
| **ai-spoke** | Project connections | Each enabled project connects to ai-hub APIM through `<project>-ai-gateway`, and to its own Storage, Search and Cosmos DB with permissions and capability hosts |
| **ai-spoke** | Workload identity and monitoring | Separate project/runtime identities, scoped permissions and dedicated telemetry per use case |
| **Both** | Private networking | Private endpoints, routing and DNS in the default profile; public workload access disabled after APIM bootstrap. Developer/runner access remains platform-provided |
| **Both** | Cost notifications | Five resource-group monthly budgets with 80% and 100% notifications; budgets are not spending caps |

Terraform manages the gateway Entra application and caller app-role assignments.
Bicep requires the explicit identity-helper steps. Both projects initially share
the same three-model access contract; limits and metrics distinguish caller identities.

The default has five user-managed resource groups, two VNets, two Foundry
accounts, two projects, two ACA environments, one registry, 14 private endpoints
and 15 DNS zones. ACA can also create service-managed resource groups.
Existing enterprise connectivity, security controls and private runners are not
provisioned here. Applying infrastructure does not create applications, images
or agent definitions, run paid smoke tests, or prove end-to-end connectivity.

### Estimated cost

Approximate USD retail baseline for Central US, using the rates checked
October 27, 2026 and 730 hours/month:

| Where | Service | Quantity | Estimated monthly cost |
|---|---|---|---|
| ai-hub | APIM Standard v2 | 1 unit | ~$700 |
| ai-spoke | Shared ACR Premium | 1 registry | ~$51 |
| ai-spoke | AI Search Basic | 2 services | ~$147 |
| Both | Private endpoints | 14 | ~$102 |
| Both | Private DNS zones | 15 | ~$7.50 |
| **Total baseline** | **Before usage and operational extras** | | **~$1,008/month** |
| ai-hub | Chat/embedding model tokens and Content Safety | Usage-based | Additional |
| ai-spoke | Future app compute, Storage, Cosmos DB and Key Vault usage | Usage-based | Additional |
| Both | Logs, alerts, network traffic and DNS queries | Usage-based | Additional |

The three model deployments use pay-as-you-go Data Zone Standard, not reserved
PTUs. Their token charges are **not included** in the baseline. Existing platform
connectivity/runners and future public ingress are also excluded. Budgets notify;
they do not stop spending. Recheck prices before deployment in the
[Pricing Calculator](https://azure.microsoft.com/pricing/calculator/).
This is not an invoice or a capacity guarantee.

### Model access pattern

Model deployments are centralized in the ai-hub Foundry account behind APIM.
The ai-spoke projects consume them through project-level connections, rather than
receiving duplicate model deployments. Both default projects share this catalog:

| Alias / deployment name | Model | Pinned version | Use |
|---|---|---|---|
| `fast-chat` | `gpt-6.1-sol` | `2026-09-29` | Chat; APIM defaults missing Chat Completions reasoning effort to `low` |
| `advanced-chat` | `gpt-6.1-terra` | `2026-10-26` | Complex chat; APIM defaults missing Chat Completions reasoning effort to `high` |
| `embeddings` | `text-embedding-3-large` | `1` | Retrieval/indexing through `/foundry/v1/embeddings`; not an agent chat model |

Each requests Data Zone Standard capacity 10 (model-specific allocation units,
not reserved throughput). US data-zone processing is not Central-US-only
processing. Confirm current quota, allocation, prices and model lifecycle before
deployment. `fast-chat` is a workload label, not a latency guarantee; explicit
caller reasoning settings are preserved. Validate Sol tool calling over the
Foundry gateway chat-completions path before tool-using agents rely on it.

Agent definitions select `<project>-ai-gateway/fast-chat` or
`<project>-ai-gateway/advanced-chat`, for example `ai-app-01-ai-gateway/fast-chat`.
All connection names include the project name to avoid collisions in the shared
Foundry account; the exported readiness settings supply the exact names.
Application code sends the bare alias as `model` to APIM. Alias names are also
the ai-hub deployment names, so no additional routing service or name translation
is needed. No model deployments are made inside the ai-spoke account.
Project and runtime identities have separate caller accounting; the configured
token allowance is per caller, not one pooled project budget.

APIM rejects unknown aliases with 403 and chat/embedding operation mismatches
with 400 before inference. Chat and Responses share the existing caller token
limit (default 10,000/minute), prompt checks and token metrics. Embeddings use a
separate default 60 requests/minute per caller and emit `EmbeddingTokens` from
successful response usage. LLM-specific token limiting and prompt safety policies
are not applied to embeddings; request limits and budgets are not token caps.
Existing response-ownership checks remain caller-scoped and require the
gateway-stamped chat alias for stored Responses. Responses created before alias
stamping are rejected rather than adopted.

Engineer groups receive project-scoped Foundry User access. This deployment
does not grant them model keys or direct inference roles on the ai-hub model account,
and creates no model deployments in the ai-spoke account. This is not a blanket
deny against inherited permissions, new connections or externally deployed models.
The static project list is discovery configuration; APIM separately enforces the
same three-alias contract for every authorized caller. Different model
entitlements per project are not implemented. Stronger restrictions require an
explicit per-project contract and review of effective permissions and platform
controls.

## Architecture

```mermaid
flowchart LR
    engineers["AI engineers<br/>Project-scoped Entra access<br/>Approved private access required"]
    enterprise["Existing enterprise platform<br/>Optional private access / routing / DNS<br/>Not provisioned here"]

    subgraph ai_spokes["sub-ai-spokes-nonprod"]
        direction TB
        subgraph spokes_infra["rg-ai-spokes-infra-nonprod-cus"]
            spokes_network["ai-spoke VNet / NSGs / private endpoints<br/>Dedicated ACA subnets / shared Agent Service subnet"]
            registry["Shared private ACR Premium"]
            subgraph foundry["Shared private Foundry account"]
                app01_project["ai-app-01 project<br/>Project identity / connections / capability host"]
                app02_project["ai-app-02 project<br/>Project identity / connections / capability host"]
            end
        end
        subgraph app01_rg["rg-ai-app-01-dev-cus"]
            app01_runtime["Internal ACA environment<br/>Runtime identity / monitoring"]
            app01_data["Private Storage / Search / Cosmos DB / Key Vault"]
        end
        subgraph app02_rg["rg-ai-app-02-dev-cus"]
            app02_runtime["Internal ACA environment<br/>Runtime identity / monitoring"]
            app02_data["Private Storage / Search / Cosmos DB / Key Vault"]
        end
        spokes_network --- app01_runtime
        spokes_network --- app02_runtime
        app01_project -->|"BYO service connections"| app01_data
        app02_project -->|"BYO service connections"| app02_data
    end

    subgraph ai_hub["sub-ai-hub-nonprod"]
        direction TB
        subgraph hub_infra["rg-ai-hub-infra-nonprod-cus"]
            hub_network["ai-hub VNet / NSGs<br/>APIM integration subnet / private endpoints"]
            shared_ops["Shared private DNS<br/>Azure Monitor Private Link Scope"]
        end
        subgraph hub_services["rg-ai-hub-services-nonprod-cus"]
            gateway["Private APIM Standard v2<br/>Model/operation allowlist / Entra / usage metrics<br/>Chat token limits / embedding request limits / alerts"]
            safety["Private Content Safety"]
            models["Private Foundry model account<br/>fast-chat / advanced-chat / embeddings"]
        end
        hub_network --- gateway
        gateway -->|"Prompt checks / managed identity"| safety
        gateway -->|"Inference / managed identity"| models
    end

    engineers --> app01_project
    engineers --> app02_project
    spokes_network <-->|"Bilateral VNet peering"| hub_network
    shared_ops --- hub_network
    shared_ops --- spokes_network
    app01_runtime -.->|"Future app model calls"| gateway
    app02_runtime -.->|"Future app model calls"| gateway
    foundry -->|"Project managed identity model connections"| gateway
    enterprise -.-> spokes_network
    enterprise -.-> hub_network

    classDef network fill:#eff6ff,stroke:#2563eb,color:#0f172a
    classDef gateway fill:#ecfdf5,stroke:#059669,color:#0f172a
    classDef external fill:#f8fafc,stroke:#64748b,color:#0f172a
    class spokes_network,hub_network,shared_ops network
    class gateway,safety,models gateway
    class enterprise,engineers external
```

The five resource groups are ownership boundaries, not VNets. Foundry projects
stay under the shared account; their backing services and ACA environments are
dedicated to each use case. Private endpoints stay in the infrastructure groups.

Solid links show configured relationships in the default profile. Dashed links
show optional platform integration or future application model calls. Each
Foundry project has a `<project>-ai-gateway` connection; an agent must select
`<project>-ai-gateway/<model-deployment-name>`. Apps and agents must use APIM, never the model account
directly. ACR and shared runtime monitoring belong to the ai-spoke foundation;
each use case also has its own telemetry. Existing-network mode uses
customer-managed routing and DNS.
See the [editable canvas](docs/reference-architecture.canvas).

## Technical notes

- **Private services:** public access is disabled on the workload services.
  APIM uses inbound Private Link and outbound VNet integration; its subnet stays
  in the platform subscription. ACR needs Premium and Search needs Basic or higher.
- **Networking:** two non-overlapping VNets are peered in both directions. One
  private DNS authority is linked to both networks. The repo creates these
  resources by default, or accepts approved `existing_networks` inputs.
- **Existing platform:** supplied VNets/zones retain their original ownership.
  Existing-network mode requires the customer to supply working routing and DNS.
  It does not automatically reuse an existing registry, logging workspace or AMPLS.
- **Agent readiness:** `enable_agent_infrastructure=true` provisions private
  Standard Agent Service connections, backing permissions and capability hosts.
  No agent is created. ACA and Foundry-hosted code agents are separate runtime
  choices; applications and images belong to a later phase.
- **Identity:** runtime and Foundry project identities are distinct. Model calls
  must go through APIM. Configure engineer group access and validate the selected
  Foundry-to-gateway connection before using an agent.
- **Foundry Control Plane:** use the portal management experience for the shared
  account and projects; it is not an extra RG resource. The IaC creates explicit
  project-level `ApiManagement` model connections using project managed identity,
  the gateway's Entra audience and a static approved-model list. This differs
  from resource-wide portal gateway onboarding. The central APIM stays in the
  ai-hub subscription; no second gateway or model keys are needed. The connection
  uses chat completions, not the gateway's Responses backend path.
- **Isolation:** each use case has dedicated backing services and application
  namespaces, separate from Foundry's internal stores. Foundry account settings,
  quotas and runtime networking remain shared. This profile is for trusted
  non-prod teams, not mutually untrusted tenants.
- **Public app access:** an end-user app may be public while its backends stay
  private. Each use case has its own ACA environment and subnet; the current profile
  keeps them internal. Public ingress is a separate application-phase decision.
- **Platform checks:** private developer/runner access, egress restrictions and
  business-data residency remain explicit platform decisions. Private endpoints
  alone do not provide them. APIM briefly permits public access during initial
  creation; an ordered update closes it after Private Link approval.
- **Readiness:** run the [private-access and agent smoke checks](infra/README.md#private-access-and-agent-smoke-test)
  from approved private connectivity. Preflight does not invoke models; a
  separate explicit flag creates and cleans up a small synthetic prompt agent.
  Offline checks do not certify live networking or service support.
- **Lifecycle:** review actual regional capacity and recurring charges before
  apply. Retain protected Terraform state and use a team-approved remote backend.
  No previous tenant's state should be reused for a new deployment.

## Release to AI engineers

This is the foundation for developing `ai-app-01` and `ai-app-02`, not a
ready-to-use application environment merely because Terraform applies.
Platform engineering should complete this handoff before inviting engineers:

| Release requirement | What the platform engineer must provide |
|---|---|
| Provisioned foundation | A reviewed deployment, protected Terraform state, reconciled existing identities and passing infrastructure checks |
| Private access | Working developer/runner connectivity and private DNS; no public-access workaround |
| Engineer access | Approved Entra groups with project access. The default group list is empty; a supplied list applies to both projects |
| Application delivery | An approved deployment identity/pipeline with scoped app deployment, runtime identity attachment and registry push permissions; these human/pipeline grants are not provisioned automatically |
| Data and model access | Verify each runtime identity's backing-service access and APIM authorization. Engineers use Foundry agents or an authorized runtime, not model keys; a local human login does not carry the gateway's application role |
| Acceptance tests | Both chat aliases, embeddings, Foundry-to-APIM routing, required tools/data operations, access denials and telemetry; confirm alert delivery |
| Handoff | Project/gateway endpoints, model aliases, registry and environment details, deployment instructions, limits, budgets and an operational contact |

After these checks, engineers can develop and deploy their application code on
the foundation. They still own app logic, agent definitions, tools, data/indexes
and application tests. See the [private-access and smoke-test guide](infra/README.md#private-access-and-agent-smoke-test).

## Get started

Supply tenant and subscription IDs through ignored local configuration or
environment variables. The repo provisions resources into existing subscriptions;
it does not create tenants or subscriptions.

Choose [Terraform](infra/terraform/README.md) or [Bicep](infra/bicep/README.md);
do not deploy both over the same resources. Both need Azure CLI and resource/RBAC
permissions in both subscriptions. Directory identity setup differs by tool.
See the [infrastructure guide](infra/README.md) for entry points and prerequisites.

### Terraform

Use Terraform matching [versions.tf](infra/terraform/versions.tf), Python 3 and
Entra application permissions.

```bash
az login --tenant <tenant-id>
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
# Fill in tenant, both subscriptions, contact, model and engineer groups.
# Set approved operations budgets/contact and the first day of the deployment month.
terraform -chdir=infra/terraform init -lockfile=readonly
terraform -chdir=infra/terraform workspace new launchpad-nonprod
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform test
python3 -m unittest discover -s infra/terraform/tests -p 'test_*.py'
terraform -chdir=infra/terraform plan -out=tfplan
```

Select the existing workspace on subsequent runs. Review subscription placement,
costs and resource changes, then:

```bash
terraform -chdir=infra/terraform apply tfplan
bash infra/terraform/test.sh
terraform -chdir=infra/terraform plan -detailed-exitcode
```

`terraform test` is offline and uses mocked providers. `test.sh` checks the live
infrastructure through read-only management APIs: tenant/subscription boundaries,
private access, endpoint approval, peering, DNS, monitoring and model provisioning.
It does not run agents/apps, read keys or perform paid inference.

A passing infrastructure test is not a packet-flow or application test. Model
calls, image pulls, private runtime DNS, evaluations and telemetry delivery need
separate validation once an application is added.

### Bicep

Prepare the gateway's Entra application and caller authorization as described in
the [Bicep guide](infra/bicep/README.md). Then compile the subscription deployment:

```bash
az bicep build --file infra/bicep/main.bicep --stdout > /dev/null
```

Supply environment-specific parameters, review a subscription-scope `what-if`,
and deploy only after reviewing scope, permissions and costs.

Subscription display names are `sub-ai-hub-nonprod` and `sub-ai-spokes-nonprod`.
The Terraform inputs `ai_hub_subscription_id` and
`ai_spokes_subscription_id` refer to their IDs respectively. Display-name
changes do not require provider, state or resource-group renames. Here, ai-hub
means shared AI services, not an enterprise network hub or a legacy Foundry hub.

## Links and sources

### Project guides

- [Infrastructure layout, inputs and verification](infra/README.md)
- [Terraform implementation](infra/terraform/README.md)
- [Bicep implementation](infra/bicep/README.md)
- [Editable architecture canvas](docs/reference-architecture.canvas)
- [Private access, smoke test and operations](infra/README.md#private-access-and-agent-smoke-test)

### Reference implementations

- [Azure Verified Modules: AI/ML landing zone for Foundry](https://github.com/Azure/terraform-azurerm-avm-ptn-aiml-landing-zone)
- [Azure AI gateway landing zone](https://github.com/Azure/terraform-ai-gateway-landing-zone)

### Microsoft documentation

- [Microsoft Foundry architecture](https://learn.microsoft.com/azure/foundry/concepts/architecture)
- [Foundry Agent Service: use your own resources](https://learn.microsoft.com/azure/foundry/agents/how-to/use-your-own-resources)
- [API Management AI gateway capabilities](https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities)
- [API Management outbound VNet integration](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound)
- [API Management inbound private endpoints](https://learn.microsoft.com/azure/api-management/private-endpoint)
- [Azure Monitor Private Link](https://learn.microsoft.com/azure/azure-monitor/fundamentals/private-link-security)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)

### Terraform guidance

- [HashiCorp: standard module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure)
- [HashiCorp: module composition](https://developer.hashicorp.com/terraform/language/modules/develop/composition)
- [HashiCorp: style guide](https://developer.hashicorp.com/terraform/language/style)
