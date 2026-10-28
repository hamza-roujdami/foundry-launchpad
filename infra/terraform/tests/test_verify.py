import ast
import contextlib
import copy
import io
from pathlib import Path
import unittest


HUB = "11111111-1111-1111-1111-111111111111"
SPOKES = "22222222-2222-2222-2222-222222222222"
TENANT = "00000000-0000-0000-0000-000000000000"


def resource_id(subscription, resource):
    return f"/subscriptions/{subscription}/resourceGroups/test/providers/{resource}"


def contract():
    return {
        "tenant_id": TENANT,
        "subscriptions": {"ai_hub": HUB, "ai_spokes": SPOKES},
        "managed_networks": True,
        "resource_groups": {"hub": {"name": "test", "subscription_id": HUB}},
        "vnets": {
            key: {
                "id": resource_id(subscription, f"Microsoft.Network/virtualNetworks/{key}"),
                "subscription_id": subscription,
                "resource_group_name": "test",
                "name": key,
            }
            for key, subscription in (("hub", HUB), ("spokes", SPOKES))
        },
        "private_services": [{
            "id": resource_id(HUB, "Microsoft.ApiManagement/service/test"),
            "api_version": "2024-05-01",
        }],
        "monitoring_services": [
            {"id": resource_id(HUB, f"Microsoft.OperationalInsights/workspaces/logs-{index}"),
             "api_version": "2023-09-01"}
            for index in range(4)
        ],
        "private_endpoint_groups": [
            {"name": "test", "subscription_id": HUB, "expected_count": 1}
        ],
        "dns_zone_ids": [
            resource_id(HUB, "Microsoft.Network/privateDnsZones/privatelink.example.com")
        ],
        "ampls_id": resource_id(HUB, "Microsoft.Insights/privateLinkScopes/test"),
        "model": None,
        "capability_hosts": [],
    }


class VerifyTests(unittest.TestCase):
    def setUp(self):
        source = (Path(__file__).parents[1] / "verify.sh").read_text()
        python = source.split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
        tree = ast.parse(python)
        # Load the embedded verifier without invoking its CLI entry point.
        tree.body = [
            node for node in tree.body
            if isinstance(node, (ast.Import, ast.ImportFrom, ast.FunctionDef, ast.Assign))
        ]
        self.verifier = {}
        exec(compile(tree, "verify.sh", "exec"), self.verifier)
        self.calls = []
        self.data = contract()
        self.broken_peering = False

    def az(self, label, *args, expected=dict):
        self.calls.append(args)
        if args[:2] == ("account", "show"):
            return {"tenantId": TENANT}
        if args[:2] == ("group", "show"):
            return {"name": args[args.index("--name") + 1]}
        if args[:2] == ("rest", "--method"):
            return {"properties": {
                "publicNetworkAccess": "Disabled",
                "provisioningState": "Succeeded",
                "publicNetworkAccessForIngestion": "Disabled",
                "publicNetworkAccessForQuery": "Disabled",
            }}
        if args[:3] == ("network", "private-endpoint", "list"):
            return [{
                "provisioningState": "Succeeded",
                "privateLinkServiceConnections": [{
                    "privateLinkServiceConnectionState": {"status": "Approved"}
                }],
            }]
        if args[:4] == ("network", "vnet", "peering", "list"):
            if self.broken_peering:
                return []
            name = args[args.index("--vnet-name") + 1]
            remote = next(v for key, v in self.data["vnets"].items() if key != name)
            return [{"peeringState": "Connected", "remoteVirtualNetwork": {"id": remote["id"]}}]
        if args[:4] == ("network", "private-dns", "zone", "show"):
            return {"name": args[args.index("--name") + 1]}
        if args[:5] == ("network", "private-dns", "link", "vnet", "list"):
            return [
                {"virtualNetworkLinkState": "Completed", "virtualNetwork": {"id": vnet["id"]}}
                for vnet in self.data["vnets"].values()
            ]
        if args[:2] == ("resource", "show"):
            return {"properties": {"accessModeSettings": {
                "ingestionAccessMode": "PrivateOnly", "queryAccessMode": "PrivateOnly",
            }}}
        raise AssertionError(f"Unexpected Azure command: {args}")

    def run_verification(self):
        self.verifier["az"] = self.az
        self.verifier["validate_contract"](self.data)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.verifier["verify"](self.data)
        return output.getvalue()

    def test_managed_networks_check_peerings_and_only_configured_zones(self):
        self.run_verification()
        self.assertEqual(self.verifier["failed"], 0)
        self.assertEqual(sum(call[:4] == ("network", "vnet", "peering", "list") for call in self.calls), 2)
        zone_calls = [call for call in self.calls if call[:3] == ("network", "private-dns", "zone")]
        self.assertEqual(len(zone_calls), 1)
        self.assertEqual(zone_calls[0][3], "show")
        self.assertIn("privatelink.example.com", zone_calls[0])

    def test_existing_networks_do_not_assume_peering_or_dns_link_topology(self):
        self.data["managed_networks"] = False
        external = "33333333-3333-3333-3333-333333333333"
        self.data["dns_zone_ids"].append(
            resource_id(external, "Microsoft.Network/privateDnsZones/other.example.com")
            .replace("/resourceGroups/test/", "/resourceGroups/central-dns/")
        )
        output = self.run_verification()
        self.assertEqual(self.verifier["failed"], 0)
        self.assertIn("SKIP: customer-managed routing and DNS-link topology", output)
        self.assertFalse(any(call[:3] == ("network", "vnet", "peering") for call in self.calls))
        self.assertFalse(any(call[:3] == ("network", "private-dns", "link") for call in self.calls))
        zone_calls = [call for call in self.calls if call[:4] == ("network", "private-dns", "zone", "show")]
        self.assertEqual(len(zone_calls), 2)
        self.assertIn("central-dns", zone_calls[1])
        self.assertIn(external, zone_calls[1])
        self.assertTrue(any(call[:2] == ("account", "show") and external in call for call in self.calls))

    def test_missing_managed_peerings_are_failures(self):
        self.broken_peering = True
        self.run_verification()
        self.assertEqual(self.verifier["failed"], 3)

    def test_network_mode_must_be_explicit_boolean(self):
        for value in (None, "false", 0):
            with self.subTest(value=value):
                data = copy.deepcopy(self.data)
                data["managed_networks"] = value
                with self.assertRaisesRegex(ValueError, "managed_networks"):
                    self.verifier["validate_contract"](data)

    def test_invalid_dns_ids_fail_before_azure_calls(self):
        for value in ([], [None], ["not-an-id"], [
            resource_id(HUB, "Microsoft.Network/privateDnsZones/test?unexpected=true")
        ]):
            with self.subTest(value=value):
                data = copy.deepcopy(self.data)
                data["dns_zone_ids"] = value
                with self.assertRaises(ValueError):
                    self.verifier["validate_contract"](data)
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
