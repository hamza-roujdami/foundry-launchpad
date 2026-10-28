#!/usr/bin/env python3
"""Explicit operator-only Microsoft Graph bootstrap and app-role authorization."""

import argparse
import json
import os
import re
import subprocess
import sys
import uuid

GRAPH = "https://graph.microsoft.com/v1.0"
ROLE = "Gateway.Invoke"


def az(*arguments):
    result = subprocess.run(
        ["az", *arguments, "--only-show-errors", "--output", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout) if result.stdout.strip() else None


def graph(method, path, body=None):
    if path.startswith("https://") and not path.startswith(GRAPH + "/"):
        raise ValueError("Refusing a non-Microsoft Graph pagination URL")
    arguments = ["rest", "--method", method, "--uri", path if path.startswith("https://") else GRAPH + path]
    if body is not None:
        arguments += ["--headers", "Content-Type=application/json", "--body", json.dumps(body)]
    return az(*arguments)


def object_id(value):
    return str(uuid.UUID(value))


def required(name):
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"Set {name}; identifiers must not be stored in source control")
    return value


def check_tenant():
    tenant = object_id(required("AZURE_TENANT_ID"))
    if object_id(az("account", "show")["tenantId"]) != tenant:
        raise ValueError("Azure CLI is authenticated to a different tenant")


def bootstrap(deployment_name):
    owner = object_id(required("GATEWAY_OWNER_OBJECT_ID"))
    display_name = f"foundry-launchpad-{deployment_name}-gateway"
    role_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"{ROLE}.{deployment_name}"))
    role = {
        "id": role_id,
        "value": ROLE,
        "displayName": "Invoke the gateway",
        "description": "Call approved Launchpad inference APIs.",
        "allowedMemberTypes": ["Application"],
        "isEnabled": True,
    }
    applications = az("ad", "app", "list", "--display-name", display_name)
    applications = [app for app in applications if app["displayName"] == display_name]
    if len(applications) > 1:
        raise ValueError("Duplicate gateway application names; resolve ownership manually")
    if applications:
        application = graph("GET", f"/applications/{object_id(applications[0]['id'])}")
        if application.get("signInAudience") != "AzureADMyOrg":
            raise ValueError("Existing application is not single-tenant; refusing to alter it")
        roles = [{key: value for key, value in item.items() if key != "origin"} for item in application.get("appRoles", [])]
        collisions = [item for item in roles if item.get("value") == ROLE or item.get("id") == role_id]
        if collisions and any(any(item.get(key) != value for key, value in role.items()) for item in collisions):
            raise ValueError("Existing gateway role differs; review manually instead of replacing it")
        if not collisions:
            roles.append(role)
        graph("PATCH", f"/applications/{application['id']}", {
            "api": {**application.get("api", {}), "requestedAccessTokenVersion": 2},
            "appRoles": roles,
        })
    else:
        application = graph("POST", "/applications", {
            "displayName": display_name,
            "signInAudience": "AzureADMyOrg",
            "api": {"requestedAccessTokenVersion": 2},
            "appRoles": [role],
            "owners@odata.bind": [f"{GRAPH}/directoryObjects/{owner}"],
        })
    client_id = object_id(application["appId"])
    uri = f"api://{client_id}"
    uris = application.get("identifierUris", [])
    if uri not in uris:
        graph("PATCH", f"/applications/{application['id']}", {"identifierUris": [*uris, uri]})
    principals = graph("GET", f"/servicePrincipals?$filter=appId eq '{client_id}'")["value"]
    if len(principals) > 1:
        raise ValueError("Multiple service principals found; review manually")
    principal = principals[0] if principals else graph("POST", "/servicePrincipals", {
        "appId": client_id,
        "owners@odata.bind": [f"{GRAPH}/directoryObjects/{owner}"],
        "appRoleAssignmentRequired": True,
    })
    principal_id = object_id(principal["id"])
    graph("PATCH", f"/servicePrincipals/{principal_id}", {"appRoleAssignmentRequired": True})
    print(f"export GATEWAY_CLIENT_ID='{client_id}'")
    print(f"export GATEWAY_SERVICE_PRINCIPAL_OBJECT_ID='{principal_id}'")
    print(f"export GATEWAY_APP_ROLE_ID='{role_id}'")
    print("# No credential was created. Review and export these identifiers locally.")


def authorization(outputs):
    gateway = outputs["gatewayAuthorization"]["value"]
    gateway["clientId"] = object_id(gateway["clientId"])
    gateway["servicePrincipalObjectId"] = object_id(gateway["servicePrincipalObjectId"])
    gateway["appRoleId"] = object_id(gateway["appRoleId"])
    if gateway["roleValue"] != ROLE:
        raise ValueError("Unexpected gateway role value in deployment outputs")
    callers = [identity["principalId"] for identity in outputs["runtimeIdentities"]["value"]]
    callers += gateway["projectPrincipalIds"]
    return gateway, sorted({object_id(caller) for caller in callers})


def check_contract(gateway):
    principal_id = gateway["servicePrincipalObjectId"]
    principal = graph("GET", f"/servicePrincipals/{principal_id}")
    if principal["appId"] != gateway["clientId"] or principal.get("appRoleAssignmentRequired") is not True:
        raise ValueError("Gateway service principal mismatch or appRoleAssignmentRequired is not true")
    roles = [role for role in principal.get("appRoles", []) if role["id"] == gateway["appRoleId"]]
    if len(roles) != 1 or roles[0].get("value") != ROLE or not roles[0].get("isEnabled"):
        raise ValueError("Gateway.Invoke app-role ID/value/enabled state mismatch")
    if roles[0].get("allowedMemberTypes") != ["Application"]:
        raise ValueError("Gateway.Invoke must allow Application members only")
    application = az("ad", "app", "show", "--id", gateway["clientId"])
    if application.get("signInAudience") != "AzureADMyOrg":
        raise ValueError("Gateway application must be single-tenant")
    if application.get("api", {}).get("requestedAccessTokenVersion") != 2:
        raise ValueError("Gateway application must request v2 access tokens")
    if f"api://{gateway['clientId']}" not in application.get("identifierUris", []):
        raise ValueError("Gateway application identifier URI is missing")


def assign_or_verify(deployment_name, mutate):
    outputs = az(
        "deployment", "sub", "show", "--subscription", object_id(required("AZURE_AI_HUB_SUBSCRIPTION_ID")),
        "--name", deployment_name, "--query", "properties.outputs",
    )
    gateway, callers = authorization(outputs)
    check_contract(gateway)
    principal_id = gateway["servicePrincipalObjectId"]
    assignments = []
    path = f"/servicePrincipals/{principal_id}/appRoleAssignedTo"
    while path:
        page = graph("GET", path)
        assignments.extend(page["value"])
        path = page.get("@odata.nextLink")
    existing = {(assignment["principalId"], assignment["appRoleId"]) for assignment in assignments}
    missing = [caller for caller in callers if (caller, gateway["appRoleId"]) not in existing]
    if missing and not mutate:
        raise ValueError(f"{len(missing)} required Gateway.Invoke assignments are missing; run assign --execute")
    for caller in missing:
        graph("POST", f"/servicePrincipals/{principal_id}/appRoleAssignedTo", {
            "principalId": caller, "resourceId": principal_id, "appRoleId": gateway["appRoleId"],
        })
    print(f"Gateway.Invoke authorization {'assigned' if mutate else 'verified'} for {len(callers)} runtime/project identities.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["bootstrap", "assign", "verify"])
    parser.add_argument("--execute", action="store_true", help="Explicitly authorize Graph mutations; never called by Bicep or validation")
    parser.add_argument("--deployment-name", default="foundry-launchpad-nonprod", help="Naming seed for bootstrap; ARM deployment record name for assign/verify")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9-]{2,63}", args.deployment_name):
        parser.error("Use a lowercase deployment name of 3-64 letters, digits or hyphens")
    if args.operation != "verify" and not args.execute:
        parser.error("Graph writes require explicit --execute after operator approval")
    check_tenant()
    if args.operation == "bootstrap":
        bootstrap(args.deployment_name)
    else:
        assign_or_verify(args.deployment_name, args.operation == "assign")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError) as error:
        sys.exit(f"ERROR: {error}")
    except subprocess.CalledProcessError:
        sys.exit("ERROR: Azure CLI/Graph operation failed. Review operator permissions and Azure CLI diagnostics; no credentials are printed.")
