#!/usr/bin/env python3
"""Offline compiled-template contracts, topology cardinalities and policy parity."""

import collections
import contextlib
import io
import importlib.util
import json
import re
import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import patch

BASE = Path(__file__).resolve().parents[1]


def resources(template):
    value = template.get("resources", {})
    return list(value.values()) if isinstance(value, dict) else value


def resource_map(template):
    return template["resources"]


def nested(template, symbol):
    return resource_map(template)[symbol]["properties"]["template"]


def declarations(template):
    for resource in resources(template):
        if resource.get("existing"):
            continue
        yield resource
        if resource["type"].lower() == "microsoft.resources/deployments":
            yield from declarations(resource["properties"]["template"])


def cardinality(resource, path, applications, engineers):
    """Expand known compiled copy contracts; reject unrecognized loop expressions."""
    copy = resource.get("copy")
    if not copy:
        return 1
    name = copy["name"]
    count = copy["count"]
    if name == "groups":
        expected, size = "[length(parameters('names'))]", 2 if "hub-groups" in path else 1 + applications
    elif name == "nsgs":
        expected, size = "[length(variables('subnets'))]", 2 if "hub-network" in path else 2 + applications
    elif name in {"projects", "applications", "backingEndpoints", "acaDns", "projectBindings"}:
        expected, size = "[length(parameters('useCases'))]", applications
    elif name in {"hubEndpoints", "spokesEndpoints"}:
        expected, size = "[length(range(0, 2))]", 2
    elif name == "zones" or (name == "links" and resource["type"] == "Microsoft.Resources/deployments"):
        expected, size = "[length(items(variables('zoneNames')))]", 13
    elif name == "links":
        expected, size = "[length(parameters('vnetIds'))]", 2
    elif name == "endpoints":
        expected, size = "[length(variables('specs'))]", 4
    elif name == "services":
        expected, size = "[length(variables('resourceIds'))]", 2 * (2 + applications)
    elif name == "records":
        expected, size = "[length(createArray('@', '*'))]", 2
    elif name == "connections":
        expected, size = "[length(variables('connectionSpecs'))]", 3
    elif name == "operations":
        expected, size = "[length(variables('operationSpecs'))]", 6
    elif name == "engineers":
        expected, size = "[length(parameters('engineerGroupIds'))]", engineers
    else:
        raise AssertionError(f"Unrecognized resource copy contract: {name}")
    assert count == expected, (path, count, expected)
    return size


def inventory(template, applications=2, engineers=0, existing=False, agents=True, path=()):
    counts = collections.Counter()
    for resource in resources(template):
        if resource.get("existing"):
            continue
        symbol = resource.get("copy", {}).get("name", resource["name"])
        current_path = (*path, symbol)
        condition = resource.get("condition")
        if condition:
            if condition == "[equals(parameters('existingNetworks'), null())]":
                enabled = not existing
            elif condition == "[parameters('enableAgents')]":
                enabled = agents
            elif condition == "[not(equals(parameters('model'), null()))]":
                enabled = "hub-services" in path
            else:
                raise AssertionError(f"Unrecognized condition: {condition}")
            if not enabled:
                continue
        size = cardinality(resource, current_path, applications, engineers)
        counts[resource["type"].lower()] += size
        if resource["type"].lower() == "microsoft.resources/deployments":
            child = inventory(resource["properties"]["template"], applications, engineers, existing, agents, current_path)
            for kind, count in child.items():
                counts[kind] += size * count
    return counts


def canonical_policy(source):
    source = re.sub(r"<!--.*?-->", "", source, flags=re.S)
    source = re.sub(r"%\{.*?\}", "", source)
    # Terraform source uses a raw C# generic in element text. Bicep emits well-formed XML.
    source = source.replace("As<string>", "As&lt;string&gt;")
    for old, new in {
        "${tenant_id}": "tenant", "__TENANT_ID__": "tenant",
        "${client_id}": "client", "__CLIENT_ID__": "client",
        "${role}": "Gateway.Invoke",
        "${backend_url}": "https://backend.invalid/openai", "__BACKEND_URL__": "https://backend.invalid/openai",
        "${tokens_per_minute}": "10000", "__TOKENS_PER_MINUTE__": "10000",
    }.items():
        source = source.replace(old, new)

    def node(element):
        return element.tag, element.attrib, " ".join((element.text or "").split()), tuple(node(child) for child in element)

    return node(ET.fromstring(source))


class Contracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = json.loads(Path(sys.argv[1]).read_text())
        cls.parameters = json.loads(Path(sys.argv[2]).read_text())
        spec = importlib.util.spec_from_file_location("gateway_identity", BASE / "scripts/gateway-identity.py")
        cls.identity = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.identity)

    def test_default_topology(self):
        root = self.template
        self.assertEqual(root["parameters"]["location"]["defaultValue"], "centralus")
        self.assertEqual([app["name"] for app in root["parameters"]["useCases"]["defaultValue"]], ["ai-app-01", "ai-app-02"])
        self.assertEqual(root["parameters"]["model"]["defaultValue"], {
            "name": "gpt-6-sol", "version": "2026-09-22", "skuName": "DataZoneStandard", "capacity": 15,
        })
        expected = {
            "microsoft.resources/resourcegroups": 5,
            "microsoft.network/virtualnetworks": 2,
            "microsoft.network/networksecuritygroups": 6,
            "microsoft.network/virtualnetworks/virtualnetworkpeerings": 2,
            "microsoft.network/privateendpoints": 14,
            "microsoft.network/privateendpoints/privatednszonegroups": 14,
            "microsoft.network/privatednszones": 15,
            "microsoft.network/privatednszones/virtualnetworklinks": 28,
            "microsoft.cognitiveservices/accounts": 3,
            "microsoft.cognitiveservices/accounts/projects": 2,
            "microsoft.cognitiveservices/accounts/deployments": 1,
            "microsoft.cognitiveservices/accounts/projects/connections": 8,
            "microsoft.cognitiveservices/accounts/projects/capabilityhosts": 2,
            "microsoft.containerregistry/registries": 1,
            "microsoft.app/managedenvironments": 2,
            "microsoft.storage/storageaccounts": 2,
            "microsoft.search/searchservices": 2,
            "microsoft.documentdb/databaseaccounts": 2,
            "microsoft.keyvault/vaults": 2,
            "microsoft.managedidentity/userassignedidentities": 2,
            "microsoft.operationalinsights/workspaces": 4,
            "microsoft.insights/components": 4,
            "microsoft.insights/privatelinkscopes/scopedresources": 8,
            "microsoft.authorization/roleassignments": 20,
            "microsoft.documentdb/databaseaccounts/sqlroleassignments": 4,
            "microsoft.apimanagement/service/apis/operations": 6,
        }
        counts = inventory(root)
        for kind, count in expected.items():
            self.assertEqual(counts[kind], count, kind)
        # Two ordered PUT declarations manage one APIM service, not two gateway instances.
        self.assertEqual(counts["microsoft.apimanagement/service"], 2)

    def test_existing_network_and_agents_off(self):
        counts = inventory(self.template, existing=True, agents=False)
        for kind in ["microsoft.network/virtualnetworks", "microsoft.network/networksecuritygroups",
                     "microsoft.network/virtualnetworks/virtualnetworkpeerings",
                     "microsoft.cognitiveservices/accounts/projects/capabilityhosts"]:
            self.assertEqual(counts[kind], 0, kind)
        self.assertEqual(counts["microsoft.network/privatednszones"], 2)  # Only new ACA environment zones.
        self.assertEqual(counts["microsoft.network/privateendpoints"], 14)
        self.assertEqual(counts["microsoft.cognitiveservices/accounts/projects/connections"], 2)  # Tracing only.
        self.assertEqual(counts["microsoft.authorization/roleassignments"], 12)
        self.assertEqual(counts["microsoft.documentdb/databaseaccounts/sqlroleassignments"], 2)

    def test_parameterized_topology_counts(self):
        counts = inventory(self.template, applications=3, engineers=2)
        self.assertEqual(counts["microsoft.resources/resourcegroups"], 6)
        self.assertEqual(counts["microsoft.network/privateendpoints"], 18)
        self.assertEqual(counts["microsoft.network/privatednszones"], 16)
        self.assertEqual(counts["microsoft.app/managedenvironments"], 3)
        self.assertEqual(counts["microsoft.cognitiveservices/accounts/projects"], 3)
        self.assertEqual(counts["microsoft.insights/privatelinkscopes/scopedresources"], 10)
        self.assertEqual(counts["microsoft.authorization/roleassignments"], 35)

    def test_subscriptions_ownership_and_ordering(self):
        root = resource_map(self.template)
        self.assertEqual(root["hubGroups"]["subscriptionId"], "[parameters('hubSubscriptionId')]")
        self.assertEqual(root["spokesGroups"]["subscriptionId"], "[parameters('spokesSubscriptionId')]")
        self.assertEqual(root["applications"]["subscriptionId"], "[parameters('spokesSubscriptionId')]")
        for name in ["gatewayEndpoint", "hubEndpoints", "privateMonitoring"]:
            self.assertEqual(root[name]["resourceGroup"], "[variables('hubInfra')]")
        for name in ["backingEndpoints", "spokesEndpoints", "acaDns", "projects"]:
            self.assertEqual(root[name]["resourceGroup"], "[variables('spokesInfra')]")
        self.assertIn("gatewayEndpoint", root["gatewayClosure"]["dependsOn"])
        closure = nested(self.template, "gatewayClosure")
        gateway = next(resource for resource in resources(closure) if resource["type"] == "Microsoft.ApiManagement/service")
        self.assertIn("indexOf(createArray('Approved'), parameters('privateEndpointConnectionState'))", gateway["properties"]["publicNetworkAccess"])
        self.assertIn("'Disabled'", gateway["properties"]["publicNetworkAccess"])
        self.assertEqual(root["projectBindings"]["copy"]["mode"], "serial")
        projects = nested(self.template, "projects")
        self.assertEqual(resource_map(projects)["projects"]["copy"]["mode"], "serial")
        hub = nested(self.template, "hub")
        self.assertIn("policy", resource_map(hub)["operations"]["dependsOn"])

    def test_private_keyless_security_contracts(self):
        for resource in declarations(self.template):
            kind = resource["type"].lower()
            properties = resource.get("properties", {})
            if kind in {"microsoft.cognitiveservices/accounts", "microsoft.search/searchservices",
                        "microsoft.documentdb/databaseaccounts", "microsoft.containerregistry/registries",
                        "microsoft.storage/storageaccounts", "microsoft.keyvault/vaults", "microsoft.app/managedenvironments"}:
                self.assertEqual(properties["publicNetworkAccess"].lower(), "disabled", kind)
            if kind in {"microsoft.cognitiveservices/accounts", "microsoft.search/searchservices", "microsoft.documentdb/databaseaccounts"}:
                self.assertIs(properties["disableLocalAuth"], True, kind)
            if kind == "microsoft.storage/storageaccounts":
                self.assertIs(properties["allowSharedKeyAccess"], False)
                self.assertIs(properties["allowBlobPublicAccess"], False)
            if kind == "microsoft.containerregistry/registries":
                self.assertEqual(resource["sku"]["name"], "Premium")
                self.assertIs(properties["adminUserEnabled"], False)
            if kind == "microsoft.app/managedenvironments":
                self.assertIs(properties["vnetConfiguration"]["internal"], True)
            if kind in {"microsoft.operationalinsights/workspaces", "microsoft.insights/components"}:
                self.assertEqual(properties["publicNetworkAccessForIngestion"], "Disabled")
                self.assertEqual(properties["publicNetworkAccessForQuery"], "Disabled")
            if kind == "microsoft.insights/privatelinkscopes":
                self.assertEqual(properties["accessModeSettings"], {"ingestionAccessMode": "PrivateOnly", "queryAccessMode": "PrivateOnly"})
            if kind == "microsoft.apimanagement/service/diagnostics":
                self.assertIs(properties["metrics"], True)
                self.assertIs(properties["logClientIp"], False)
                for side in ["frontend", "backend"]:
                    for direction in ["request", "response"]:
                        self.assertEqual(properties[side][direction]["body"]["bytes"], 0)
            if kind == "microsoft.authorization/roleassignments":
                self.assertIn("scope", resource, "Every ARM role must be explicitly resource-scoped")
                self.assertIn(properties["principalType"], ["ServicePrincipal", "Group"])
        hub = nested(self.template, "hub")
        apim = resource_map(hub)["apim"]
        self.assertEqual(apim["sku"], {"name": "StandardV2", "capacity": 1})
        self.assertEqual(apim["properties"]["virtualNetworkType"], "External")
        key_targets = re.findall(r"listKeys\('([^']+)'", json.dumps(self.template))
        self.assertEqual(key_targets, ["workspace"], "Only ACA's Azure Monitor log-shipping integration may read a workspace key")

    def test_gateway_policy_parity(self):
        terraform = BASE.parent / "terraform/modules/ai-hub-services/gateway-policy.xml.tftpl"
        policy = (BASE / "policies/gateway.xml").read_text()
        self.assertEqual(canonical_policy(policy), canonical_policy(terraform.read_text()))
        self.assertNotIn("${", policy)
        self.assertNotIn("%{", policy)
        ET.fromstring(policy)
        hub = nested(self.template, "hub")
        operations = hub["variables"]["operationSpecs"]
        self.assertEqual({operation["id"] for operation in operations}, {
            "responses-create", "responses-get", "responses-delete", "responses-cancel",
            "responses-input-items", "chat-completions-create",
        })

    def test_example_environment_parameters(self):
        # az build-params stdout wraps parametersJson in newer CLI releases.
        parameters = self.parameters
        if "parametersJson" in parameters:
            parameters = json.loads(parameters["parametersJson"]) if isinstance(parameters["parametersJson"], str) else parameters["parametersJson"]
        parameters = parameters["parameters"]
        self.assertEqual(parameters["tenantId"]["value"], "00000000-0000-0000-0000-000000000001")
        self.assertNotEqual(parameters["hubSubscriptionId"]["value"], parameters["spokesSubscriptionId"]["value"])
        for name in ["gatewayClientId", "gatewayServicePrincipalObjectId", "gatewayAppRoleId", "publisherEmail"]:
            self.assertNotIn("defaultValue", self.template["parameters"][name])

    def test_identity_operator_safety(self):
        identity = self.identity
        ids = [f"00000000-0000-0000-0000-{i:012d}" for i in range(1, 7)]
        outputs = {
            "gatewayAuthorization": {"value": {
                "clientId": ids[0], "servicePrincipalObjectId": ids[1], "appRoleId": ids[2],
                "roleValue": "Gateway.Invoke", "projectPrincipalIds": [ids[4], ids[5]],
            }},
            "runtimeIdentities": {"value": [{"principalId": ids[3]}, {"principalId": ids[4]}]},
        }
        gateway, callers = identity.authorization(outputs)
        self.assertEqual(callers, sorted(set(ids[3:])))
        with patch.object(identity, "graph") as graph, patch.object(identity, "az", return_value=outputs), patch.object(identity, "required", return_value=ids[0]), patch.object(identity, "check_contract"):
            graph.return_value = {"value": []}
            with self.assertRaisesRegex(ValueError, "assignments are missing"):
                identity.assign_or_verify("example", False)
            self.assertTrue(all(call.args[0] == "GET" for call in graph.call_args_list))
        with self.assertRaises(ValueError):
            identity.object_id("invalid")
        with patch.object(sys, "argv", ["gateway-identity.py", "bootstrap"]), patch.object(identity, "check_tenant") as check:
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as result:
                identity.main()
            self.assertNotEqual(result.exception.code, 0)
            check.assert_not_called()

    def test_identity_bootstrap_is_idempotent(self):
        identity = self.identity
        import uuid

        deployment_name = "example-deployment"
        role_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, "Gateway.Invoke." + deployment_name))
        client_id = "00000000-0000-0000-0000-000000000001"
        principal_id = "00000000-0000-0000-0000-000000000002"
        application = {
            "id": principal_id,
            "appId": client_id,
            "displayName": f"foundry-launchpad-{deployment_name}-gateway",
            "signInAudience": "AzureADMyOrg",
            "identifierUris": ["api://" + client_id],
            "api": {"requestedAccessTokenVersion": 2},
            "appRoles": [{
                "id": role_id,
                "value": "Gateway.Invoke",
                "displayName": "Invoke the gateway",
                "description": "Call approved Launchpad inference APIs.",
                "allowedMemberTypes": ["Application"],
                "isEnabled": True,
                "origin": "Application",
            }],
        }

        def fake_graph(method, path, body=None):
            if method == "GET" and path.startswith("/applications/"):
                return application
            if method == "GET" and path.startswith("/servicePrincipals?"):
                return {"value": [{"id": principal_id, "appId": client_id}]}
            return None

        with patch.object(identity, "az", return_value=[application]), patch.object(identity, "required", return_value=principal_id), patch.object(identity, "graph", side_effect=fake_graph) as graph, contextlib.redirect_stdout(io.StringIO()):
            identity.bootstrap(deployment_name)
        self.assertTrue(all(call.args[0] != "POST" for call in graph.call_args_list))
        application_patch = next(call.args[2] for call in graph.call_args_list if call.args[0] == "PATCH" and call.args[1].startswith("/applications/"))
        self.assertNotIn("origin", application_patch["appRoles"][0])


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=2)
