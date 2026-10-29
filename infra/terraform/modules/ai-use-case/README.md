# AI use case

One use case's internal ACA environment, runtime identity, private backing
services, telemetry and Foundry project connections. No app, job, image, model
deployment or agent definition is created.

The root supplies the shared Foundry project, registry, dedicated ACA subnet and
central gateway contract. With Agent Service enabled, the project gets three
backing connections and one `<project>-ai-gateway` model connection using its managed
identity. Agent definitions select `<project>-ai-gateway/fast-chat` or
`<project>-ai-gateway/advanced-chat`. Embeddings are available through the gateway for
application code, not included in the agent chat-model list.
Backing services and ACA belong to the use-case group; endpoints and environment
DNS belong to the supplied AI spokes infrastructure group.

Providers are configured by the root. See [inputs](variables.tf),
[outputs](outputs.tf) and the [root guide](../../README.md).
