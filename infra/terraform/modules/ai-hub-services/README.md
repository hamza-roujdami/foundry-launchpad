# AI hub services

Shared private APIM AI gateway, Foundry model hosting, Content Safety and
telemetry in the AI hub services resource group. No use-case runtime is created.
The caller supplies network/DNS IDs, Entra audience, model allocation and contact.
Private endpoints belong to the supplied hub infrastructure group.

Providers are configured by the root. See [inputs](variables.tf) and
[outputs](outputs.tf); the [root guide](../../README.md) shows composition,
validation and deployment. The versioned policy is
[gateway-policy.xml.tftpl](gateway-policy.xml.tftpl).
