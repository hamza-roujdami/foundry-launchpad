# Infrastructure

Choose one implementation of the same ai-hub and ai-spoke architecture:

| Implementation | Entry point | Guide |
|---|---|---|
| Terraform | [terraform/main.tf](terraform/main.tf) | [Terraform guide](terraform/README.md) |
| Bicep | [bicep/main.bicep](bicep/main.bicep) | [Bicep guide](bicep/README.md) |

Both target two existing subscriptions in one Entra tenant, five resource groups,
shared model access through APIM, and dedicated infrastructure for `ai-app-01`
and `ai-app-02`. See the [architecture and cost estimate](../README.md).

Do not deploy both implementations over the same resources. Use isolated
subscriptions for independent installations, or plan an explicit ownership
migration. Changing a deployment name alone does not isolate the resource groups.
Terraform state and ARM deployment history are not interchangeable.

Terraform manages the gateway's Entra application and role assignments through
its AzureAD provider. Bicep's ARM templates require directory identity preparation
as documented in its guide; provisioning Azure resources alone is not sufficient
to authorize callers. Its identity helper is an explicit operator step, never
automatically invoked by template compilation or deployment. The Bicep guide also
documents the initial APIM private-access bootstrap and redeployment setting.

Neither implementation deploys business applications, agent definitions,
container images or public application ingress. Compilation and offline tests
do not establish live connectivity or regional capacity.
Before handing this environment to developers, complete the
[AI engineer release checklist](../README.md#release-to-ai-engineers).
Project access does not automatically grant app deployment, registry push or
direct local gateway access. Keep those permissions scoped to the required
resources and use an approved deployment/runtime identity.

## Private access and agent smoke test

Use an existing platform-managed private runner or workstation with approved
VPN/ExpressRoute connectivity. Do not add a public IP or enable public service
access to run these checks. This repo does not provision VPN, Bastion or a runner.
The deployment operator needs Azure CLI access, resource read permissions on the
selected project and gateway, and project-scoped Foundry User (or equivalent
agent/conversation permissions). With Bicep, finish the explicit gateway
app-role assignments before inference.

The platform owner must provide:

- Routes from the runner to the workload endpoint subnets, plus TCP 443 access.
- Private DNS resolution for APIM, Foundry, ACR, Storage, Search, Cosmos and
  Key Vault. An on-premises/VPN client needs forwarding to the platform's Azure
  DNS resolver; VNet zone links alone do not configure laptop DNS.
- Routing and private DNS from the Foundry Agent Service subnet to APIM.
  Default new-network mode supplies the workload peering and zone links.
  Existing-network mode requires the equivalent platform configuration.
- Approved access to Entra and Azure management endpoints. Private endpoints
  are not outbound internet controls.

After an approved deployment, export only the non-secret readiness contract.
These commands read outputs; they do not deploy infrastructure:

```bash
# Terraform:
terraform -chdir=infra/terraform output -json readiness > infra/readiness.json

# OR Bicep (use the actual deployment name):
az deployment sub show --subscription "$AZURE_AI_HUB_SUBSCRIPTION_ID" \
  --name foundry-launchpad-nonprod --query properties.outputs.readiness.value \
  --output json > infra/readiness.json

python3 infra/scripts/smoke.py --config infra/readiness.json --use-case ai-app-01
```

The default preflight checks all seven service hostnames for exclusively
RFC1918 addresses, opens certificate-validated TLS connections, requires HTTP
401 for an unauthenticated gateway request, and reads the deployed model
connection and APIM public-access setting. Failure exits nonzero. No credentials
or request bodies are printed. The output file is ignored by Git.

Preflight proves the **runner's** network path, not the agent subnet's path.
Once a paid synthetic test is approved, use Python 3.10+ and the pinned SDKs:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r infra/scripts/requirements-smoke.txt
.venv/bin/python infra/scripts/smoke.py --config infra/readiness.json \
  --use-case ai-app-01 --allow-paid-inference
```

This creates one uniquely named prompt agent using
`ai-gateway/fast-chat`, makes one synthetic request with an output
token limit, and requires the exact `LAUNCHPAD_OK` reply. It deletes the
conversation and temporary agent on success or inference failure. Cleanup
failure is an error; if creation times out or the process is interrupted, inspect
the reported `launchpad-smoke-<run-id>` name and remove any remaining test agent
and conversation. It does not deploy an app, push an image or read business data.
The command uses the current Azure CLI identity, not a model key.

Repeat with `--agent-model advanced-chat` to test the second agent model.
The simple agent smoke does not certify tool calling. In particular, verify
Sol's tool behavior over the gateway chat-completions path separately because
Microsoft's model documentation is inconsistent about that combination.

To test all three aliases directly, run from approved private compute that
already has one of the exported runtime managed identities attached. Do not
grant the gateway app role to a human account to make the test pass. The Azure
CLI identity still needs read-only preflight permissions; inference uses the
specified managed identity:

```bash
.venv/bin/python infra/scripts/smoke.py --config infra/readiness.json \
  --use-case ai-app-01 --allow-paid-inference \
  --gateway-runtime-client-id "$RUNTIME_CLIENT_ID"
```

This mode checks rejection of an unknown model (403) and a chat/embedding
mismatch (400), then makes two chat calls and one embedding call. It requires
completed chat replies with positive usage and one finite 3072-dimensional
embedding vector, matching the default `text-embedding-3-large`. It creates no
agent. It validates the runtime-to-APIM path, not the Foundry Agent Service path;
run both modes before declaring the whole environment ready.

The client invokes the Foundry **agent** endpoint. The project's managed identity
then calls APIM with its `Gateway.Invoke` role; APIM's identity calls the model.
The gateway leg uses `/foundry/v1/chat/completions` with `api-version=v1`. A bare
model name is rejected by the test. This path does not assume BYOM support for
the gateway's separate Responses backend API.

After a successful run, use the printed UTC time to inspect the hub's
Application Insights `requests` and `dependencies`: confirm the
`/foundry/v1/chat/completions` request and model dependency, plus caller token
metrics and the `EmbeddingTokens` custom metric for the embeddings test. Query
from private connectivity because AMPLS is private-only. Log
arrival is asynchronous; missing telemetry is a remaining acceptance failure,
not proof that monitoring works. The smoke does **not** certify image pulls,
all backing-service data operations, safety attacks or token-limit saturation.
Validate those with the eventual app, without weakening controls.

Python regression tests use the standard library. The policy-expression test
also requires the .NET 10 SDK and uses its bundled Newtonsoft.Json assembly:
it executes the actual C# expressions extracted from the policy without NuGet
downloads or Azure calls. Without the SDK, that test explicitly skips; CI
installs the SDK. These tests are not a substitute for Azure's policy validation.

```bash
python3 -m unittest discover -s infra/tests -p 'test_*.py'
```

## Basic operational controls

Both implementations require an `operations` input: notification email, stable
budget start date (the first day of the initial deployment month), and monthly
amounts for hub infrastructure, hub services, spokes infrastructure and each app.
Amounts use the subscription's billing currency. Example numbers are illustrative,
not approval to spend. Retain the start date on later deployments.

- Five resource-group budgets notify at 80% and 100% of actual monthly cost.
  They do not automatically stop services and cost data is delayed.
- One hub action group receives gateway alerts: at least five 5xx responses or
  ten 429 responses in five minutes, evaluated every minute. A 429 can be an
  intentional caller limit, backend quota exhaustion or capacity pressure.
- Confirm notification delivery through Azure Monitor's action-group test.
  Review caller metrics and backend capacity before changing token allowances.
- Budgets cover their resource groups, not ACA's separate service-managed groups
  or existing platform costs. Include those in the platform's cost review.
- Deployment permissions must include resource-group budget writes and monitor
  action-group/metric-alert writes; register Microsoft.Consumption through the
  platform process. Do not grant subscription roles to application identities.

The default layout remains two trusted non-prod use cases. Before substantial
growth, review endpoint subnet capacity: the `/26` is not sized for the maximum
16 accepted use cases. Separate engineer-group membership and independent
per-project token allowances are also separate scaling decisions.

## References

- [Foundry models behind an AI gateway](https://learn.microsoft.com/azure/foundry/agents/how-to/ai-gateway)
- [Official project-managed-identity APIM connection sample](https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/apim/modules/apim-connection-common.bicep)
- [APIM model discovery and routing contract](https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/apim/APIM-Connection-Objects.md)
- [Foundry private access](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link)
- [APIM monitoring metrics](https://learn.microsoft.com/azure/azure-monitor/reference/supported-metrics/microsoft-apimanagement-service-metrics)
- [Azure budget schema](https://learn.microsoft.com/azure/templates/microsoft.consumption/2024-08-01/budgets)
- [Foundry model capabilities](https://learn.microsoft.com/azure/foundry/foundry-models/concepts/models-sold-directly-by-azure)
- [LLM token limit supported APIs](https://learn.microsoft.com/azure/api-management/llm-token-limit-policy)
- [Request rate limiting](https://learn.microsoft.com/azure/api-management/rate-limit-by-key-policy)
- [Custom token metrics](https://learn.microsoft.com/azure/api-management/emit-metric-policy)
