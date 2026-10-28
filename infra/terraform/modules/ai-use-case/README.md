# AI use case

One use case's internal ACA environment, runtime identity, private backing
services, telemetry and Foundry project connections. No app, job, image, model
deployment or agent definition is created.

The root supplies the shared Foundry project, registry and dedicated ACA subnet.
Backing services and ACA belong to the use-case group; endpoints and environment
DNS belong to the supplied AI spokes infrastructure group.

Providers are configured by the root. See [inputs](variables.tf),
[outputs](outputs.tf) and the [root guide](../../README.md).
