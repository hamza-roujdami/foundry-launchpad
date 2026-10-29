# Bicep deployment alternative

Subscription-scoped ARM/Bicep implementation of the
[Launchpad architecture](../../README.md). Choose **one** implementation per
deployment; do not manage the same resources with both tools.

## Code layout

- `main.bicep`: cross-subscription resource groups, module composition and outputs.
- `main.bicepparam`: environment-based parameter example.
- `types.bicep`: shared parameter and output types.
- `modules/ai-hub-services.bicep`: gateway, model hosting, safety and monitoring.
- `modules/ai-spokes-services.bicep`: shared Foundry, registry and monitoring.
- `modules/ai-use-case.bicep`: dedicated application infrastructure.
- `modules/budget.bicep`, `modules/gateway-alerts.bicep`: resource-group budgets and gateway alerts.
- Other modules handle resource-group scopes, networking, project bindings and
  ordered private access.
- `policies/`: versioned gateway policy.
- `scripts/`: explicit directory-identity operations and offline validation.
- `validate.sh`: compilation and regression-test entry point.

## Architecture and ownership

The default is Central US, two existing subscriptions in one Entra tenant, and
`ai-app-01` / `ai-app-02`:

| Subscription | Resource group | Owned resources |
|---|---|---|
| Hub | `rg-ai-hub-infra-nonprod-cus` | Hub VNet, NSGs, APIM delegated subnet, private endpoints, 13 shared DNS zones linked to both VNets, AMPLS |
| Hub | `rg-ai-hub-services-nonprod-cus` | Standard v2 APIM, model-only Foundry S0, Content Safety S0, gateway policy, monitoring |
| Spokes | `rg-ai-spokes-infra-nonprod-cus` | Spokes VNet, NSGs, delegated agent/ACA subnets, Premium ACR, shared Foundry S0 with two projects, shared monitoring, private endpoints and ACA DNS |
| Spokes | `rg-ai-app-01-dev-cus` | Internal ACA environment, runtime identity, monitoring, Storage LRS, Search Basic, Cosmos serverless and Key Vault |
| Spokes | `rg-ai-app-02-dev-cus` | The same dedicated application infrastructure for the second use case |

Hub infrastructure/services remain platform-owned. Shared spokes infrastructure
and project accounts stay outside application resource groups; engineers own
their application groups. Private endpoints stay in infrastructure groups.
No application, image, agent definition, tenant, subscription or landing zone is
created.

Default structural counts: **5 groups, 2 VNets, 6 NSGs, 2 bilateral peerings,
2 Foundry accounts, 2 projects, 1 registry, 2 ACA environments, 14 private
endpoints, 15 DNS zones, 4 workspaces and 4 Application Insights components**.
The third Cognitive Services account is Content Safety. Two ordered APIM PUTs
manage **one** service. ARM nested deployments are orchestration resources;
their counts are not comparable to Terraform's managed-resource count.
The default also creates five resource-group budgets, one operational action
group and two gateway metric alerts.

### Security and policy parity

- Public access is disabled on workload services. Foundry, Storage, Search
  and Cosmos use Entra authentication; registry admin access is off; vault
  authorization uses RBAC with purge protection.
- APIM has inbound Private Link **and** outbound VNet integration in the hub
  subscription. New networks use the Terraform subnet layout: endpoint `/26`,
  hub APIM `/27`, spokes Agent Service `/24`, and dedicated ACA `/23` slots.
  NSGs retain the same Azure default rules; no new public ingress is added.
- `policies/gateway.xml` preserves the Terraform Responses/chat routes,
  tenant/audience/app-role checks, verified-caller token accounting, prompt
  safety/shield checks, metrics, retry/streaming behavior, and response ownership
  checks for reads, deletes, cancellations, input items and continuations.
  Model calls use APIM's identity, never engineer-held model keys. XML placeholders
  are replaced with Bicep `replace(loadTextContent(...))`; no Terraform directives
  or `${...}` template placeholders remain.
- Runtime permissions are scoped to the project, registry, vault, application
  blob container, search service and application Cosmos database. Agent Service
  permissions are distinct: account-level Blob Data Owner and Cosmos data access
  for agent-owned stores, Cosmos DB Operator, and Search contributor/data roles.
  Engineer groups receive project-scoped Foundry User, not subscription roles.
- Agent infrastructure adds creation-time network injection, AAD BYO
  Storage/Search/Cosmos connections and serial project capability hosts.
  Foundry account/project writes are serialized where required.
- Each enabled project gets a `<project>-ai-gateway` model connection using
  `ProjectManagedIdentity`, audience `api://<gateway-client-id>` and the static
  approved chat-model list. It targets the central APIM `/foundry/v1` route across
  subscriptions. Agents select `<project>-ai-gateway/fast-chat` or
  `<project>-ai-gateway/advanced-chat`; no key is read. Application embeddings use APIM's
  `/foundry/v1/embeddings` operation and the `embeddings` alias.
  All connection names are project-qualified to avoid shared-account collisions.
  Capability-host connection bindings are immutable: changing existing names
  requires a reviewed host replacement, not an ordinary in-place update.
- APIM enforces the same three-alias model/operation allowlist for both projects,
  retaining caller-scoped response ownership. Chat token limits and prompt safety
  are separate from the embedding request limit (default 60/minute per caller)
  and successful-response `EmbeddingTokens` metric.
- All four monitoring pairs are attached to a PrivateOnly AMPLS. APIM enables
  token metrics but logs zero request/response body bytes and no client IP.
  ACA's log-shipping integration reads a Log Analytics workspace key internally;
  Foundry tracing stores the Application Insights connection string in the
  service connection. These are service-managed telemetry integration values,
  not model credentials, parameters or outputs.

### Important implementation differences

1. **Entra is deliberately out of band.** ARM cannot create the gateway
   application or app-role assignments. Required inputs are `gatewayClientId`,
   `gatewayServicePrincipalObjectId` and `gatewayAppRoleId`. Azure RBAC is fully
   provisioned in Bicep; Entra app roles are **not** silently treated as RBAC.
   The explicit operator steps below are required before inference works.
2. Names use Bicep `uniqueString`, not Terraform SHA1. The architectures match;
   resource names/IDs and state do not. Do not deploy this over Terraform-managed
   groups as a migration strategy, or manage one resource from both tools.
3. This implementation targets Azure public cloud. Foundry project endpoints
   and gateway Entra authorities use public-cloud domains. No alternate-cloud
   certification or region/model substitution is implied.
4. Narrowly scoped schema suppressions preserve the documented preview REST
   contracts as Terraform: backend `credentials.managedIdentity` and project
   `capabilityHostKind: Agents`, plus the official APIM connection sample's
   `ProjectManagedIdentity` authentication and `audience`. Bicep 0.46.1's bundled
   type catalog omits these contracts. The remaining resources/properties are typed; there is no `any()`,
   generated template blob, deployment script or automatic Graph extension.
   These preview service contracts still require live deployment verification.

## Required operator preparation

Obtain approval for the target tenant, both subscriptions, Central US, resources,
networking and costs **before** running any write operation below. Use an
approved deployment identity with resource-group deployment permissions in both
subscriptions, resource-scoped role-assignment write permissions, subnet joins,
Private Link approval and private DNS zone-group/link permissions.
Register the required providers in both subscriptions through the platform
process, including Microsoft.Web for APIM delegation and Microsoft.App for ACA.
Microsoft.Consumption must be registered in both subscriptions for RG budgets.
No provider registration is performed by these templates.

The `models` input requests **`fast-chat` -> `gpt-6.1-sol` (`2026-09-29`)**,
**`advanced-chat` -> `gpt-6.1-terra` (`2026-10-26`)**, and
**`embeddings` -> `text-embedding-3-large` (`1`)**, each with
`DataZoneStandard` capacity `10`. The deployment names are the aliases.
Confirm availability, capacity units, quota and region before deployment; compilation
does not validate the catalog or guarantee allocation. No reservation is bought
and no region is silently inferred from the model name.
This replaces the former singular `model` parameter; update local parameter
files and review existing model deployments before redeploying.

Supply identifiers/contact through environment variables used by
`main.bicepparam`, never checked-in customer values:

```text
AZURE_TENANT_ID
AZURE_AI_HUB_SUBSCRIPTION_ID
AZURE_AI_SPOKES_SUBSCRIPTION_ID
GATEWAY_CLIENT_ID
GATEWAY_SERVICE_PRINCIPAL_OBJECT_ID
GATEWAY_APP_ROLE_ID
APIM_PUBLISHER_EMAIL
OPERATIONS_EMAIL
BUDGET_START_DATE
BUDGET_HUB_INFRA
BUDGET_HUB_SERVICES
BUDGET_SPOKES_INFRA
BUDGET_PER_APP
```

Budget amounts must be approved positive integers in billing currency. Set the
start date to the first day of the initial deployment month
(`YYYY-MM-01T00:00:00Z`) and retain it on redeploy. Budgets alert at 80%/100%;
they are not spending caps. See [operational controls](../README.md#basic-operational-controls).

### Entra bootstrap and authorization — explicit, never automatic

Use an existing approved single-tenant app, or have an authorized Entra operator
run the optional script. It uses Microsoft Graph **v1.0**, not a Bicep extension.
Graph authorization is separate from ARM deployment permissions: app creation/
updates require suitable application-management permissions; app-role grants
require `AppRoleAssignment.ReadWrite.All` and `Application.Read.All` plus the
appropriate supported administrator role (for example Application Administrator
or Cloud Application Administrator for this non-Graph resource application).
Do not grant these directory-wide privileges to an application runtime.

The application contract is:

- `signInAudience = AzureADMyOrg`; `api.requestedAccessTokenVersion = 2`.
- Identifier URI `api://<gatewayClientId>`.
- Enabled application-only role **`Gateway.Invoke`**, whose UUID is the
  `gatewayAppRoleId` input. The helper uses Terraform's deterministic UUIDv5
  seed `Gateway.Invoke.<deploymentName>` in the DNS namespace.
- A corresponding enterprise application with `appRoleAssignmentRequired=true`.
- One app-role assignment per runtime managed identity and, when agent
  infrastructure is enabled, per Foundry project identity. The assignment's
  `principalId` is the caller identity object ID, `resourceId` is the gateway
  enterprise application object ID, and `appRoleId` is the enabled role UUID.

After change approval and authenticating the Azure CLI to the correct tenant:

```bash
# Optional BEFORE ARM: also set GATEWAY_OWNER_OBJECT_ID to the approved owner.
# Creates/updates only this gateway app/SP, no secret or certificate.
python3 infra/bicep/scripts/gateway-identity.py bootstrap --execute
# Review and export the three identifiers printed by the helper.
```

After a successful approved ARM deployment:

```bash
# Explicit Graph mutation; derives all caller object IDs from deployment outputs.
python3 infra/bicep/scripts/gateway-identity.py assign --execute \
  --deployment-name foundry-launchpad-nonprod
# Read-only check of app contract and every required caller assignment.
python3 infra/bicep/scripts/gateway-identity.py verify \
  --deployment-name foundry-launchpad-nonprod
```

The script checks the tenant and gateway contract, deduplicates callers and
does not re-grant existing assignments. `bootstrap` and `assign` refuse to run
without `--execute`. Bicep, validation and CI **never invoke them**. Manual
provisioning with the identical properties/assignments above is supported.
If the ARM deployment record name differs from the naming seed, use the naming
seed for bootstrap and the actual record name for assign/verify.

Request application tokens for `api://<gatewayClientId>/.default`. Application
and agent code must use the `gatewayUrl` output, not the model account endpoint.
Configuring/testing the Foundry-to-APIM model connection remains a separate
live acceptance task; the IaC already creates the keyless project-to-APIM
connection, as in Terraform. No direct model connection is added.

## Offline validation

Requires existing Azure CLI with **Bicep 0.46.1** and Python 3 standard library.
No login, package installation, Azure query, Graph call or paid run is needed.

```bash
bash infra/bicep/validate.sh
# Standalone compilation, with no generated JSON committed:
az bicep build --file infra/bicep/main.bicep --no-restore --stdout > /dev/null
# Uses your local environment for the example parameters:
az bicep build-params --file infra/bicep/main.bicepparam --no-restore --stdout > /dev/null
```

Validation uses synthetic identifiers, compiles both files, checks topology
cardinalities, existing-network/agents-off contracts, scoped permissions,
network/keyless controls, APIM closure/policy ordering, parsed policy parity and
operator-script safety. Its scratch directory is created **under this project**
and removed on exit; nothing is written to system temporary directories.
These are structural smoke tests, not an ARM expression evaluator, cloud
what-if, live service validation or end-to-end inference test.

## What-if and deployment — instructions only

After the identity inputs, private-network runner/access and quota are approved:

```bash
az deployment sub what-if \
  --subscription "$AZURE_AI_HUB_SUBSCRIPTION_ID" \
  --location centralus --name foundry-launchpad-nonprod \
  --parameters infra/bicep/main.bicepparam

# Execute ONLY after reviewing/approving the complete cross-subscription what-if:
az deployment sub create \
  --subscription "$AZURE_AI_HUB_SUBSCRIPTION_ID" \
  --location centralus --name foundry-launchpad-nonprod \
  --parameters infra/bicep/main.bicepparam
```

`bootstrapGatewayPublicAccess=true` is required for **first APIM creation**:
Azure requires an approved gateway private endpoint before disabling public
access. The DAG is `hub -> gatewayEndpoint -> gatewayClosure`; the closure
reissues the APIM configuration with public access disabled, and rejects any
connection state other than `Approved` before that PUT. Operations are created
only after the authentication/ownership policy is installed.

**Change `bootstrapGatewayPublicAccess` to `false` for every subsequent
deployment**, including what-if, so an already-private gateway is not reopened.
A failed first deployment before closure can leave APIM's public gateway enabled;
do not use it or declare success. Resolve endpoint approval and complete closure,
then verify the actual service's public access is `Disabled`. Never work around
this by weakening RBAC, network rules or policy.

Inspect deployment outputs: `gatewayUrl`, `gatewayPublicNetworkAccess`,
`projects`, `runtimeIdentities`, `backingServices`, `registry`,
`containerAppEnvironmentIds`, `gatewayAuthorization` and `readiness`.
After authorization, use an approved private runner to verify DNS/peering,
telemetry ingestion, gateway token limits/safety, response ownership and denial
of public/direct-model access. Identity propagation or preview capability-host
provisioning may require a reviewed retry; no automatic role broadening occurs.
Export `readiness` for the shared [private preflight and opt-in agent smoke test](../README.md#private-access-and-agent-smoke-test).

## Existing network mode

Set `existingNetworks` in a local parameter file to reuse platform VNets,
delegated subnets and DNS authority. Bicep does **not** modify/create those
VNets, NSGs, subnet delegations, peerings, shared zones or links in this mode.
It still creates workload private endpoints, DNS zone groups, AMPLS, registry,
monitoring and the two ACA environment DNS zones in workload infrastructure
groups, exactly as Terraform's existing-network mode does.

```bicep
param existingNetworks = {
  hub: {
    vnetId: readEnvironmentVariable('HUB_VNET_ID')
    privateEndpointSubnetId: readEnvironmentVariable('HUB_PE_SUBNET_ID')
    apimSubnetId: readEnvironmentVariable('HUB_APIM_SUBNET_ID')
    dnsZoneIds: {
      apim: readEnvironmentVariable('DNS_APIM_ID')
      cognitiveservices: readEnvironmentVariable('DNS_COGNITIVE_ID')
      openai: readEnvironmentVariable('DNS_OPENAI_ID')
      servicesai: readEnvironmentVariable('DNS_SERVICESAI_ID')
      acr: readEnvironmentVariable('DNS_ACR_ID')
      blob: readEnvironmentVariable('DNS_BLOB_ID')
      search: readEnvironmentVariable('DNS_SEARCH_ID')
      cosmos: readEnvironmentVariable('DNS_COSMOS_ID')
      keyvault: readEnvironmentVariable('DNS_KEYVAULT_ID')
      monitor: readEnvironmentVariable('DNS_MONITOR_ID')
      oms: readEnvironmentVariable('DNS_OMS_ID')
      ods: readEnvironmentVariable('DNS_ODS_ID')
      automation: readEnvironmentVariable('DNS_AUTOMATION_ID')
    }
  }
  spokes: {
    vnetId: readEnvironmentVariable('SPOKES_VNET_ID')
    privateEndpointSubnetId: readEnvironmentVariable('SPOKES_PE_SUBNET_ID')
    agentSubnetId: readEnvironmentVariable('SPOKES_AGENT_SUBNET_ID')
    acaSubnetIds: {
      'ai-app-01': readEnvironmentVariable('APP01_ACA_SUBNET_ID')
      'ai-app-02': readEnvironmentVariable('APP02_ACA_SUBNET_ID')
    }
  }
}
```

Zone IDs can refer to different resource groups/subscriptions, including
enterprise central DNS. The deployment identity must have the needed rights
on each zone. Platform-managed resolution must already work from **both**
networks, including forwarding/routing/links. APIM's subnet must be in the hub
subscription and same region as APIM. Each ACA subnet must be dedicated and
delegated to Microsoft.App/environments; the agent subnet uses the same service
delegation. Do not change creation-time Foundry network injection in place.

For new-network mode, supply distinct, non-overlapping IPv4 `/16` prefixes and
unique stable subnet slots `1..31`. Use-case names must match Terraform's
lowercase naming restrictions; duplicate names/slots and overlapping address
spaces are invalid. Review these cross-field constraints before what-if;
ARM parameter decorators do not enforce Terraform's complete regex/set logic.

## Costs and sources

The root README's Central US estimate (about **$1,008/month fixed before usage**
for the default profile) applies to either implementation, not to the Bicep
deployment-resource count. Verify current prices, model availability and quota.
APIM, Premium ACR, Search, Private Link, DNS, model tokens, log ingestion,
Cosmos/Storage operations and future compute incur charges; nothing is deployed
free merely because validation is offline.

References:

- [APIM outbound VNet integration](https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound)
- [APIM private endpoints and disabling public access](https://learn.microsoft.com/azure/api-management/private-endpoint)
- [Content Safety policy and backend managed identity](https://learn.microsoft.com/azure/api-management/llm-content-safety-policy)
- [Foundry account preview schema](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2025-04-01-preview/accounts)
- [Foundry project capability-host schema](https://learn.microsoft.com/azure/templates/microsoft.cognitiveservices/2025-04-01-preview/accounts/projects/capabilityhosts)
- [Foundry private-network standard setup sample](https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15-private-network-standard-agent-setup)
- [Graph app-role assignment contract](https://learn.microsoft.com/graph/api/serviceprincipal-post-approleassignedto?view=graph-rest-1.0)
- [Foundry and other AI role definitions](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/ai-machine-learning)

The [root README](../../README.md) defines the architecture. Compilation does
not validate live connectivity, regional capacity or Entra authorization.
