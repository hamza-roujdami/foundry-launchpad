# Foundry

An Entra-authenticated Foundry account, its projects, optional model deployments
and optional private endpoint. The AI hub uses it for model hosting; AI spokes
use it for the shared account and use-case projects.

The caller supplies networking and DNS references. Use-case connections and
backing services are composed separately, not created by this module.
See [inputs](variables.tf), [outputs](outputs.tf) and the
[root guide](../../README.md).
