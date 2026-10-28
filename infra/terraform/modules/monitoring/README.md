# Monitoring

Log Analytics and Application Insights for a service boundary. The caller chooses
private access and supplies the resource group, name and tags. Sensitive telemetry
configuration outputs remain marked sensitive.

The root associates these resources with its shared Azure Monitor Private Link
Scope; this module does not create another AMPLS or DNS authority.
See [inputs](variables.tf), [outputs](outputs.tf) and the
[root guide](../../README.md).
