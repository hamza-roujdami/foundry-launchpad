#!/usr/bin/env bash
# Offline only: no login, Azure queries, Graph calls, deployment, package installation or global config changes.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workdir="$root/infra/bicep/.validation-$$"
mkdir "$workdir"
trap 'rm -rf -- "$workdir"' EXIT

export AZURE_BICEP_CHECK_VERSION=false
export PYTHONDONTWRITEBYTECODE=1
# Synthetic non-customer identifiers used only to compile the checked-in parameter example.
export AZURE_TENANT_ID=00000000-0000-0000-0000-000000000001
export AZURE_AI_HUB_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000002
export AZURE_AI_SPOKES_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000003
export GATEWAY_CLIENT_ID=00000000-0000-0000-0000-000000000004
export GATEWAY_SERVICE_PRINCIPAL_OBJECT_ID=00000000-0000-0000-0000-000000000005
export GATEWAY_APP_ROLE_ID=00000000-0000-0000-0000-000000000006
export APIM_PUBLISHER_EMAIL=validation@example.invalid

az bicep build --file "$root/infra/bicep/main.bicep" --no-restore --stdout > "$workdir/main.json"
az bicep build-params --file "$root/infra/bicep/main.bicepparam" --no-restore --stdout > "$workdir/parameters.json"
python3 "$root/infra/bicep/scripts/validate.py" "$workdir/main.json" "$workdir/parameters.json"
