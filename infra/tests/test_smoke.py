import contextlib
import importlib.util
import io
import json
import socket
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch


SPEC = importlib.util.spec_from_file_location("smoke", Path(__file__).parents[1] / "scripts/smoke.py")
smoke = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = smoke
SPEC.loader.exec_module(smoke)


def fixture():
    return {
        "name": "ai-app-01",
        "project_id": "/subscriptions/test/resourceGroups/spokes/providers/Microsoft.CognitiveServices/accounts/foundry/projects/ai-app-01",
        "project_endpoint": "https://foundry.services.ai.azure.com/api/projects/ai-app-01",
        "gateway_url": "https://gateway.azure-api.net/foundry/v1",
        "gateway_audience": "api://00000000-0000-0000-0000-000000000001",
        "gateway_id": "/subscriptions/test/resourceGroups/hub/providers/Microsoft.ApiManagement/service/gateway",
        "connection_name": "ai-gateway",
        "model": "fast-chat",
        "agent_model": "ai-gateway/fast-chat",
        "agents_enabled": True,
        "registry_url": "https://registry.azurecr.io",
        "private_urls": [
            "https://storage.blob.core.windows.net",
            "https://search.search.windows.net",
            "https://cosmos.documents.azure.com",
            "https://vault.vault.azure.net",
        ],
    }


class SmokeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "readiness.json"
        self.write(fixture())

    def write(self, entry):
        self.path.write_text(json.dumps([entry]))

    def config(self):
        return smoke.load_configuration(self.path, "ai-app-01")

    def test_selects_gateway_model_only(self):
        self.assertEqual(self.config().agent_model, "ai-gateway/fast-chat")
        for field, value in [("agent_model", "test-model"), ("gateway_url", "https://direct.openai.azure.com/openai/v1"), ("agents_enabled", False)]:
            with self.subTest(field=field):
                entry = fixture()
                entry[field] = value
                self.write(entry)
                with self.assertRaises(ValueError):
                    self.config()

    def test_rejects_missing_or_ambiguous_inputs(self):
        for value in [{}, [], [fixture(), fixture()]]:
            self.path.write_text(json.dumps(value))
            with self.assertRaises(ValueError):
                self.config()
        entry = fixture()
        entry["private_urls"] = []
        self.write(entry)
        with self.assertRaises(ValueError):
            self.config()

    def test_rejects_credentials_and_non_https_urls(self):
        for url in ["http://gateway.example", "https://user:secret@gateway.example", "https://gateway.example?key=secret", "https://gateway.example:8443"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                smoke.https_host(url)

    def test_private_dns_requires_every_address_to_be_private(self):
        def result(address):
            return (socket.AF_INET, socket.SOCK_STREAM, 6, "", (address, 443))
        with patch.object(socket, "getaddrinfo", return_value=[result("10.41.0.10")]):
            self.assertEqual(smoke.private_addresses("test.example"), ["10.41.0.10"])
        for addresses in [["20.1.1.1"], ["10.41.0.10", "20.1.1.1"], ["127.0.0.1"], ["169.254.169.254"], []]:
            with patch.object(socket, "getaddrinfo", return_value=[result(ip) for ip in addresses]), self.assertRaises(RuntimeError):
                smoke.private_addresses("test.example")

    def test_gateway_requires_401_not_generic_failure(self):
        for status in [200, 302, 401, 403, 404, 500]:
            connection = MagicMock()
            connection.getresponse.return_value.status = status
            with patch.object(smoke.http.client, "HTTPSConnection", return_value=connection), contextlib.redirect_stdout(io.StringIO()):
                if status == 401:
                    smoke.check_unauthorized_gateway(fixture()["gateway_url"])
                else:
                    with self.assertRaises(RuntimeError):
                        smoke.check_unauthorized_gateway(fixture()["gateway_url"])
            connection.close.assert_called_once()

    def test_deployed_connection_cannot_use_keys_or_wrong_audience(self):
        config = self.config()
        properties = {
            "category": "ApiManagement",
            "authType": "ProjectManagedIdentity",
            "audience": config.gateway_audience,
            "target": config.gateway_url,
            "metadata": {"deploymentInPath": "false", "inferenceAPIVersion": "v1", "models": json.dumps([{"name": "fast-chat"}, {"name": "advanced-chat"}])},
        }
        for key, value in [(None, None), ("authType", "ApiKey"), ("audience", "https://cognitiveservices.azure.com"), ("target", "https://direct.openai.azure.com")]:
            candidate = {**properties, **({key: value} if key else {})}
            with patch.object(smoke, "arm_get", side_effect=[{"properties": candidate}, {"properties": {"publicNetworkAccess": "Disabled"}}]), contextlib.redirect_stdout(io.StringIO()):
                if key:
                    with self.assertRaises(RuntimeError):
                        smoke.check_connection(config)
                else:
                    smoke.check_connection(config)
        with patch.object(smoke, "arm_get", side_effect=[{"properties": properties}, {"properties": {"publicNetworkAccess": "Enabled"}}]), self.assertRaises(RuntimeError):
            smoke.check_connection(config)

    def test_no_inference_without_opt_in_and_no_success_on_preflight_failure(self):
        args = ["--config", str(self.path), "--use-case", "ai-app-01"]
        with patch.object(smoke, "preflight"), patch.object(smoke, "run_agent") as run, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(smoke.main(args), 0)
            run.assert_not_called()
            self.assertEqual(smoke.main([*args, "--allow-paid-inference"]), 0)
            run.assert_called_once()
        with patch.object(smoke, "preflight", side_effect=RuntimeError("DNS unavailable")), patch.object(smoke, "run_agent") as run, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(smoke.main([*args, "--allow-paid-inference"]), 1)
            run.assert_not_called()

    def test_agent_model_routing_and_cleanup_on_success_and_failure(self):
        for failure in [None, RuntimeError("inference failed")]:
            project = MagicMock()
            project.agents.create_version.return_value = SimpleNamespace(name="temporary-agent", version="1")
            client = project.get_openai_client.return_value.__enter__.return_value
            client.conversations.create.return_value = SimpleNamespace(id="conversation")
            client.responses.create.side_effect = failure
            client.responses.create.return_value = SimpleNamespace(status="completed", output_text="LAUNCHPAD_OK")
            definition = MagicMock()
            with contextlib.redirect_stdout(io.StringIO()):
                if failure:
                    with self.assertRaises(RuntimeError):
                        smoke.exercise_agent(project, definition, self.config(), "test-run")
                else:
                    smoke.exercise_agent(project, definition, self.config(), "test-run")
            self.assertEqual(definition.call_args.kwargs["model"], "ai-gateway/fast-chat")
            client.conversations.delete.assert_called_once_with("conversation")
            project.agents.delete.assert_called_once_with(agent_name="temporary-agent")
            self.assertEqual(client.responses.create.call_args.kwargs["max_output_tokens"], 256)
            self.assertEqual(client.responses.create.call_args.kwargs["extra_body"]["agent_reference"]["version"], "1")

    def test_agent_rejects_incomplete_response_and_cleanup_failure(self):
        project = MagicMock()
        project.agents.create_version.return_value = SimpleNamespace(name="temporary-agent", version="1")
        client = project.get_openai_client.return_value.__enter__.return_value
        client.conversations.create.return_value = SimpleNamespace(id="conversation")
        for status, text in [("incomplete", "LAUNCHPAD_OK"), ("completed", "unexpected")]:
            client.responses.create.return_value = SimpleNamespace(status=status, output_text=text)
            with self.assertRaises(RuntimeError):
                smoke.exercise_agent(project, MagicMock(), self.config(), "test-run")
        client.responses.create.return_value = SimpleNamespace(status="completed", output_text="LAUNCHPAD_OK")
        client.conversations.delete.side_effect = RuntimeError("cleanup failed")
        with self.assertRaisesRegex(RuntimeError, "cleanup failed"):
            smoke.exercise_agent(project, MagicMock(), self.config(), "test-run")

    def test_gateway_smoke_checks_rejections_usage_and_vector_dimensions(self):
        class StatusError(Exception):
            def __init__(self, status):
                self.status_code = status
        client = MagicMock()
        chat = SimpleNamespace(choices=[SimpleNamespace(finish_reason="stop", message=SimpleNamespace(content="LAUNCHPAD_OK"))], usage=SimpleNamespace(total_tokens=5))
        client.chat.completions.create.side_effect = [StatusError(403), StatusError(400), chat, chat]
        vector = SimpleNamespace(data=[SimpleNamespace(embedding=[0.1] * 3072)], usage=SimpleNamespace(total_tokens=5))
        client.embeddings.create.return_value = vector
        with contextlib.redirect_stdout(io.StringIO()):
            smoke.exercise_gateway(client, StatusError)
        self.assertEqual([call.kwargs["model"] for call in client.chat.completions.create.call_args_list], ["unapproved-model", "embeddings", "advanced-chat", "fast-chat"])
        client.embeddings.create.assert_called_once_with(model="embeddings", input="Synthetic Launchpad readiness check.", encoding_format="float")
        for dimension in [0, 1536]:
            client.chat.completions.create.side_effect = [StatusError(403), StatusError(400), chat, chat]
            vector.data[0].embedding = [0.1] * dimension
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(RuntimeError, "3072"):
                smoke.exercise_gateway(client, StatusError)
        client.chat.completions.create.side_effect = [StatusError(401)]
        with self.assertRaisesRegex(RuntimeError, "expected 403"):
            smoke.exercise_gateway(client, StatusError)

    def test_agent_selection_and_gateway_identity_are_explicit(self):
        args = ["--config", str(self.path), "--use-case", "ai-app-01", "--allow-paid-inference"]
        with patch.object(smoke, "preflight"), patch.object(smoke, "run_agent") as agent, patch.object(smoke, "run_gateway") as gateway:
            self.assertEqual(smoke.main([*args, "--agent-model", "advanced-chat"]), 0)
            self.assertEqual(agent.call_args.args[0].agent_model, "ai-gateway/advanced-chat")
            gateway.assert_not_called()
            client_id = "00000000-0000-0000-0000-000000000001"
            self.assertEqual(smoke.main([*args, "--gateway-runtime-client-id", client_id]), 0)
            self.assertEqual(gateway.call_args.args[1], client_id)


if __name__ == "__main__":
    unittest.main()
