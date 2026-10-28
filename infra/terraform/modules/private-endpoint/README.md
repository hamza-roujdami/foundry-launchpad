# Private endpoint

A private endpoint and DNS zone group for one supplied target/subresource.
The caller supplies the owning network group, subnet and existing private DNS
zone IDs. This module does not create the target service, VNet or DNS zones.

Providers are inherited from the caller. See [inputs](variables.tf) and the
[root guide](../../README.md). Consumers use the target resource ID, so no
endpoint outputs are needed.
