#!/usr/bin/env bash
# Read-only control-plane verification; never sends model requests or reads keys.
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  printf 'FAIL: python3 is required\nSummary: 0 passed, 1 failed\n' >&2
  exit 1
fi

infra_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 - "$infra_dir" <<'PY'
import json
import subprocess
import sys

passed = failed = 0


def check(label, condition):
    global passed, failed
    if condition:
        passed += 1
    else:
        failed += 1
    print(f"{'PASS' if condition else 'FAIL'}: {label}", flush=True)


def read_json(label, command, expected=dict):
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=120, check=False
        )
        if result.returncode:
            raise ValueError(f"command exited {result.returncode}")
        data = json.loads(result.stdout)
        if not isinstance(data, expected):
            raise ValueError(f"expected JSON {expected.__name__}")
        if expected is list and any(not isinstance(item, dict) for item in data):
            raise ValueError("expected a list of JSON objects")
        return data
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        # Do not echo CLI output: it can contain sensitive resource details.
        reason = str(error) if isinstance(error, ValueError) else type(error).__name__
        check(f"{label} ({reason})", False)
        return None


def az(label, *args, expected=dict):
    return read_json(
        label, ["az", *args, "--only-show-errors", "--output", "json"], expected
    )


def properties(resource):
    value = resource.get("properties")
    return value if isinstance(value, dict) else {}


def nested(resource, key):
    value = resource.get(key)
    return value if isinstance(value, dict) else {}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def strings(record, keys, label):
    require(isinstance(record, dict), f"{label} must be an object")
    for key in keys:
        require(
            isinstance(record.get(key), str) and bool(record[key].strip()),
            f"{label}.{key} must be a nonempty string",
        )


def resource_get(label, resource):
    return az(
        label, "rest", "--method", "get", "--url",
        f"https://management.azure.com{resource['id']}?api-version={resource['api_version']}",
    )


def dns_zones(data):
    ids = data.get("dns_zone_ids")
    require(isinstance(ids, list) and bool(ids), "dns_zone_ids must be a nonempty list")
    zones = []
    for resource_id in ids:
        require(isinstance(resource_id, str), "DNS zone IDs must be strings")
        parts = resource_id.split("/")
        require(
            len(parts) == 9 and parts[0] == ""
            and parts[1].lower() == "subscriptions"
            and parts[3].lower() == "resourcegroups"
            and parts[5].lower() == "providers"
            and parts[6].lower() == "microsoft.network"
            and parts[7].lower() == "privatednszones"
            and all(parts[index].strip() for index in (2, 4, 8))
            and "?" not in resource_id and "#" not in resource_id,
            "expected a private DNS zone resource ID",
        )
        zones.append({"name": parts[8], "subscription_id": parts[2], "resource_group_name": parts[4]})
    return zones


def validate_contract(data):
    strings(data, ["tenant_id", "ampls_id"], "verification")
    strings(data.get("subscriptions"), ["ai_hub", "ai_spokes"], "subscriptions")
    subscriptions = data["subscriptions"]
    require(
        subscriptions["ai_hub"].lower() != subscriptions["ai_spokes"].lower(),
        "AI hub and AI spokes subscriptions must differ",
    )
    for key in ("resource_groups", "vnets"):
        require(isinstance(data.get(key), dict) and bool(data[key]), f"{key} is missing or empty")
    require(len(data["vnets"]) == 2, "expected exactly two VNets")
    for key, group in data["resource_groups"].items():
        strings(group, ["name", "subscription_id"], f"resource_groups.{key}")
    for key, vnet in data["vnets"].items():
        strings(vnet, ["id", "subscription_id", "resource_group_name", "name"], f"vnets.{key}")
    for key in ("private_services", "monitoring_services", "private_endpoint_groups", "capability_hosts"):
        if key == "capability_hosts":
            require(isinstance(data.get(key), list), "capability_hosts must be a list")
            for index, item in enumerate(data[key]):
                strings(item, ["id", "api_version"], f"capability_hosts[{index}]")
            continue
        require(isinstance(data.get(key), list) and bool(data[key]), f"{key} is missing or empty")
        fields = ["name", "subscription_id"] if key == "private_endpoint_groups" else ["id", "api_version"]
        for index, item in enumerate(data[key]):
            strings(item, fields, f"{key}[{index}]")
    require(len(data["monitoring_services"]) >= 4, "expected AI hub and use-case monitoring resources")
    require(
        len({item["id"].lower() for item in data["monitoring_services"]}) == len(data["monitoring_services"]),
        "monitoring resource IDs must be distinct",
    )
    require(isinstance(data.get("managed_networks"), bool), "managed_networks must be a boolean")
    dns_zones(data)
    require(isinstance(data.get("models"), list) and len(data["models"]) == 3, "models must contain all three governed deployments")
    for model in data["models"]:
        strings(model, ["id", "api_version"], "model")
    require({model["id"].rsplit("/", 1)[-1] for model in data["models"]} == {"fast-chat", "advanced-chat", "embeddings"}, "models must contain each governed alias exactly once")
    ids = [data["ampls_id"], *(v["id"] for v in data["vnets"].values())]
    ids += [v["id"] for key in ("private_services", "monitoring_services") for v in data[key]]
    ids += [model["id"] for model in data["models"]]
    ids += [host["id"] for host in data["capability_hosts"]]
    allowed = {value.lower() for value in subscriptions.values()}
    for resource_id in ids:
        parts = resource_id.split("/")
        require(
            len(parts) >= 5 and parts[0] == "" and parts[1].lower() == "subscriptions"
            and parts[2].lower() in allowed and "?" not in resource_id and "#" not in resource_id,
            "resource IDs must belong to a configured subscription",
        )
    for record in [
        *data["resource_groups"].values(), *data["vnets"].values(),
        *data["private_endpoint_groups"],
    ]:
        require(record["subscription_id"].lower() in allowed, "unexpected subscription in verification output")


def verify(data):
    for name in ("ai_hub", "ai_spokes"):
        account = az(
            f"{name} subscription", "account", "show",
            "--subscription", data["subscriptions"][name],
        )
        if account is not None:
            check(f"{name} subscription tenant", str(account.get("tenantId", "")).lower() == data["tenant_id"].lower())

    dns_subscriptions = {zone["subscription_id"] for zone in dns_zones(data)}
    for dns_subscription in sorted(dns_subscriptions):
        if dns_subscription.lower() in {value.lower() for value in data["subscriptions"].values()}:
            continue
        account = az("central DNS subscription", "account", "show", "--subscription", dns_subscription)
        if account is not None:
            check("central DNS subscription tenant", str(account.get("tenantId", "")).lower() == data["tenant_id"].lower())

    for key, group in data["resource_groups"].items():
        result = az(
            f"resource group {key}", "group", "show",
            "--subscription", group["subscription_id"], "--name", group["name"],
        )
        if result is not None:
            check(f"resource group {key} exists", result.get("name") == group["name"])

    for index, service in enumerate(data["private_services"], 1):
        label = f"private service {service['id'].rsplit('/', 1)[-1]}"
        result = resource_get(label, service)
        if result is not None:
            check(f"{label} public access Disabled", properties(result).get("publicNetworkAccess") == "Disabled")
            state = properties(result).get("provisioningState")
            if state is not None:
                check(f"{label} provisioning Succeeded", state == "Succeeded")

    for group in data["private_endpoint_groups"]:
        label = f"private endpoints in {group['name']}"
        endpoints = az(
            label, "network", "private-endpoint", "list",
            "--subscription", group["subscription_id"], "--resource-group", group["name"],
            expected=list,
        )
        if endpoints is None:
            continue
        check(f"{label} exist", bool(endpoints))
        check(f"{label} expected count", len(endpoints) == group["expected_count"])
        for index, endpoint in enumerate(endpoints, 1):
            check(f"{label} #{index} Succeeded", endpoint.get("provisioningState") == "Succeeded")
            connections = (
                (endpoint.get("privateLinkServiceConnections") or [])
                + (endpoint.get("manualPrivateLinkServiceConnections") or [])
            )
            check(
                f"{label} #{index} Approved",
                bool(connections) and all(
                    isinstance(connection, dict)
                    and nested(connection, "privateLinkServiceConnectionState").get("status") == "Approved"
                    for connection in connections
                ),
            )

    vnets = list(data["vnets"].values())
    vnet_ids = {vnet["id"].lower() for vnet in vnets}
    require(len(vnet_ids) == 2, "expected two distinct VNet IDs")
    if data["managed_networks"]:
        peering_count = 0
        for vnet in vnets:
            label = f"peerings for {vnet['name']}"
            peerings = az(
                label, "network", "vnet", "peering", "list",
                "--subscription", vnet["subscription_id"],
                "--resource-group", vnet["resource_group_name"], "--vnet-name", vnet["name"],
                expected=list,
            )
            if peerings is None:
                continue
            expected_remote = vnet_ids - {vnet["id"].lower()}
            peerings = [
                peering for peering in peerings
                if str(nested(peering, "remoteVirtualNetwork").get("id", "")).lower() in expected_remote
            ]
            peering_count += len(peerings)
            check(f"{label} count is 1", len(peerings) == 1)
            for index, peering in enumerate(peerings, 1):
                check(
                    f"{label} #{index} Connected to other VNet",
                    peering.get("peeringState") == "Connected"
                    and str(nested(peering, "remoteVirtualNetwork").get("id", "")).lower() in expected_remote,
                )
        check("bilateral peering count is 2", peering_count == 2)
    else:
        print("SKIP: customer-managed routing and DNS-link topology; validate connectivity from a private runner")

    for zone in dns_zones(data):
        name = zone["name"]
        result = az(
            f"private DNS zone {name}", "network", "private-dns", "zone", "show",
            "--subscription", zone["subscription_id"],
            "--resource-group", zone["resource_group_name"], "--name", name,
        )
        if result is not None:
            check(f"private DNS zone {name} exists", result.get("name") == name)
        if data["managed_networks"]:
            links = az(
                f"DNS links for {name}", "network", "private-dns", "link", "vnet", "list",
                "--subscription", zone["subscription_id"], "--resource-group", zone["resource_group_name"],
                "--zone-name", name, expected=list,
            )
            if links is not None:
                links = [
                    link for link in links
                    if str(nested(link, "virtualNetwork").get("id", "")).lower() in vnet_ids
                ]
                check(f"{name} DNS link count is 2", len(links) == 2)
                check(
                    f"{name} links target both VNets",
                    {str(nested(link, "virtualNetwork").get("id", "")).lower() for link in links} == vnet_ids,
                )
                for link_index, link in enumerate(links, 1):
                    check(f"{name} link #{link_index} Completed", link.get("virtualNetworkLinkState") == "Completed")

    scope = az("AMPLS", "resource", "show", "--ids", data["ampls_id"])
    if scope is not None:
        modes = nested(properties(scope), "accessModeSettings")
        for mode in ("ingestionAccessMode", "queryAccessMode"):
            check(f"AMPLS {mode} PrivateOnly", modes.get(mode) == "PrivateOnly")
        # Per-endpoint exclusions must not override PrivateOnly.
        for index, exclusion in enumerate(modes.get("exclusions") or [], 1):
            check(
                f"AMPLS exclusion #{index} PrivateOnly",
                isinstance(exclusion, dict)
                and exclusion.get("ingestionAccessMode") == "PrivateOnly"
                and exclusion.get("queryAccessMode") == "PrivateOnly",
            )

    for index, service in enumerate(data["monitoring_services"], 1):
        label = f"monitoring resource {index}"
        result = resource_get(label, service)
        if result is not None:
            for setting in ("publicNetworkAccessForIngestion", "publicNetworkAccessForQuery"):
                check(f"{label} {setting} Disabled", properties(result).get(setting) == "Disabled")

    for deployment in data["models"]:
        label = f"model deployment {deployment['id'].rsplit('/', 1)[-1]}"
        model = resource_get(label, deployment)
        if model is not None:
            check(f"{label} Succeeded", properties(model).get("provisioningState") == "Succeeded")

    for host in data["capability_hosts"]:
        label = f"capability host {host['id'].split('/projects/')[1].split('/')[0]}"
        result = resource_get(label, host)
        if result is not None:
            check(f"{label} Succeeded", properties(result).get("provisioningState") == "Succeeded")
            for connection in ("storageConnections", "threadStorageConnections", "vectorStoreConnections"):
                check(f"{label} {connection} configured", bool(properties(result).get(connection)))


try:
    output = read_json(
        "Terraform verification output",
        ["terraform", f"-chdir={sys.argv[1]}", "output", "-json", "verification"],
    )
    if output is not None:
        validate_contract(output)
        check("Terraform verification output contract", True)
        verify(output)
except (ValueError, TypeError, KeyError, AttributeError) as error:
    check(f"verification data invalid ({type(error).__name__})", False)
print(f"Summary: {passed} passed, {failed} failed", flush=True)
sys.exit(1 if failed else 0)
PY
