# Infrastructure

Choose one implementation of the same AI hub and spokes architecture:

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
