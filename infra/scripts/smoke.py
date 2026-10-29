#!/usr/bin/env python3
"""Private-access preflight and explicitly opted-in, synthetic Foundry agent smoke test."""

import argparse
import http.client
import ipaddress
import json
import math
import re
import socket
import ssl
import subprocess
import sys
import uuid
from contextlib import ExitStack
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable
from urllib.parse import urlsplit


PRIVATE_NETWORKS = tuple(ipaddress.ip_network(cidr) for cidr in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))
EXPECTED_REPLY = "LAUNCHPAD_OK"
CHAT_ALIASES = {"fast-chat", "advanced-chat"}


@dataclass(frozen=True)
class Configuration:
    name: str
    project_id: str
    project_endpoint: str
    gateway_url: str
    gateway_audience: str
    gateway_id: str
    connection_name: str
    model: str
    agent_model: str
    registry_url: str
    private_urls: tuple[str, ...]


def https_host(url: str) -> str:
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.port not in (None, 443):
        raise ValueError("Endpoint must be an HTTPS URL on port 443 without credentials, query or fragment.")
    return parsed.hostname


def load_configuration(path: Path, use_case: str) -> Configuration:
    entries = json.loads(path.read_text())
    if not isinstance(entries, list):
        raise ValueError("Export the readiness output value: expected an array of use-case configurations.")
    matches = [entry for entry in entries if isinstance(entry, dict) and entry.get("name") == use_case]
    if len(matches) != 1:
        raise ValueError("Select exactly one use case present in the readiness output.")
    entry = matches[0]
    fields = set(Configuration.__dataclass_fields__) - {"private_urls"}
    if any(not isinstance(entry.get(key), str) or not entry[key] for key in fields):
        raise ValueError("Readiness output is missing a required string field; regenerate it after deployment.")
    urls = entry.get("private_urls")
    if not isinstance(urls, list) or len(urls) != 4 or any(not isinstance(url, str) for url in urls):
        raise ValueError("Readiness output must contain all four backing-service URLs.")
    if entry.get("agents_enabled") is not True:
        raise ValueError("Enable Agent Service infrastructure before running this readiness test.")
    config = Configuration(**{key: entry[key] for key in fields}, private_urls=tuple(urls))
    for url in (config.project_endpoint, config.gateway_url, config.registry_url, *config.private_urls):
        https_host(url)
    if not re.fullmatch(r"/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.CognitiveServices/accounts/[^/]+/projects/[^/]+", config.project_id):
        raise ValueError("Invalid Foundry project ARM resource ID.")
    if not re.fullmatch(r"/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.ApiManagement/service/[^/]+", config.gateway_id):
        raise ValueError("Invalid APIM ARM resource ID.")
    if config.connection_name != f"{config.name}-ai-gateway" or config.model not in CHAT_ALIASES or config.agent_model != f"{config.connection_name}/{config.model}":
        raise ValueError("The smoke agent must select the ai-gateway connection, never a direct model deployment.")
    if not re.fullmatch(r"api://[0-9a-fA-F-]{36}", config.gateway_audience):
        raise ValueError("Expected the gateway's Entra application audience.")
    if not config.gateway_url.endswith("/foundry/v1"):
        raise ValueError("Expected Launchpad's /foundry/v1 gateway route.")
    return config


def private_addresses(host: str) -> list[str]:
    addresses = sorted({item[4][0] for item in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)})
    if not addresses:
        raise RuntimeError(f"No DNS addresses for {host}.")
    for address in addresses:
        ip = ipaddress.ip_address(address)
        if not any(ip in network for network in PRIVATE_NETWORKS):
            raise RuntimeError(f"{host} does not resolve exclusively to RFC1918 private addresses; check private DNS.")
    return addresses


def check_private_tls(url: str) -> None:
    host = https_host(url)
    context = ssl.create_default_context()
    for address in private_addresses(host):
        with socket.create_connection((address, 443), timeout=10) as stream:
            with context.wrap_socket(stream, server_hostname=host):
                pass
    print(f"PASS private DNS/TLS: {host}")


def check_unauthorized_gateway(url: str) -> None:
    connection = http.client.HTTPSConnection(https_host(url), timeout=20)
    try:
        connection.request("POST", f"{urlsplit(url).path}/chat/completions", body="{}", headers={"Content-Type": "application/json"})
        response = connection.getresponse()
        if response.status != 401:
            raise RuntimeError(f"Unauthenticated gateway request returned {response.status}, expected 401.")
    finally:
        connection.close()
    print("PASS gateway rejects unauthenticated inference")


def arm_get(resource_id: str, api_version: str) -> dict:
    result = subprocess.run(
        ["az", "rest", "--method", "get", "--url", f"https://management.azure.com{resource_id}?api-version={api_version}", "--output", "json", "--only-show-errors"],
        capture_output=True, text=True, timeout=60, check=False,
    )
    if result.returncode:
        raise RuntimeError("Azure management read failed. Check az login, the active tenant, and read permissions on the project and gateway.")
    body = json.loads(result.stdout)
    if not isinstance(body, dict):
        raise RuntimeError("Azure management read did not return a resource object.")
    return body


def check_connection(config: Configuration) -> None:
    properties = arm_get(f"{config.project_id}/connections/{config.connection_name}", "2025-04-01-preview").get("properties", {})
    expected = {
        "category": "ApiManagement",
        "authType": "ProjectManagedIdentity",
        "audience": config.gateway_audience,
        "target": config.gateway_url,
    }
    if any(properties.get(key) != value for key, value in expected.items()):
        raise RuntimeError("Foundry connection does not match the keyless central gateway contract.")
    metadata = properties.get("metadata", {})
    if metadata.get("deploymentInPath") != "false":
        raise RuntimeError("Foundry connection must use OpenAI-style body-based model routing.")
    if metadata.get("inferenceAPIVersion") != "v1":
        raise RuntimeError("Foundry connection must select the gateway's v1 inference API.")
    models = json.loads(metadata.get("models", "null"))
    if not isinstance(models, list) or len(models) != 2 or any(not isinstance(model, dict) for model in models) or {model.get("name") for model in models} != CHAT_ALIASES:
        raise RuntimeError("Foundry connection must expose exactly fast-chat and advanced-chat, not the embeddings model.")
    gateway = arm_get(config.gateway_id, "2024-05-01").get("properties", {})
    if gateway.get("publicNetworkAccess") != "Disabled":
        raise RuntimeError("APIM public access is not disabled; finish the ordered private-access deployment.")
    print("PASS deployed Foundry model connection and private gateway configuration")


def preflight(config: Configuration) -> None:
    for url in dict.fromkeys((config.gateway_url, config.project_endpoint, config.registry_url, *config.private_urls)):
        check_private_tls(url)
    check_unauthorized_gateway(config.gateway_url)
    check_connection(config)


def exercise_agent(project, definition_factory: Callable, config: Configuration, run_id: str) -> None:
    with ExitStack() as cleanup:
        agent = project.agents.create_version(
            agent_name=f"launchpad-smoke-{run_id}",
            definition=definition_factory(model=config.agent_model, instructions=f"Reply with exactly {EXPECTED_REPLY}."),
        )
        cleanup.callback(project.agents.delete, agent_name=agent.name)
        client = cleanup.enter_context(project.get_openai_client(timeout=120, max_retries=0))
        conversation = client.conversations.create()
        cleanup.callback(client.conversations.delete, conversation.id)
        response = client.responses.create(
            conversation=conversation.id,
            input="Return the readiness confirmation.",
            max_output_tokens=256,
            extra_body={"agent_reference": {"name": agent.name, "version": agent.version, "type": "agent_reference"}},
        )
        if response.status != "completed" or response.output_text.strip() != EXPECTED_REPLY:
            raise RuntimeError("Agent response did not complete with the expected synthetic confirmation.")
    print("PASS synthetic Foundry agent -> APIM -> model; temporary agent and conversation deleted")


def run_agent(config: Configuration) -> None:
    try:
        from azure.ai.projects import AIProjectClient
        from azure.ai.projects.models import PromptAgentDefinition
        from azure.core.exceptions import AzureError
        from azure.identity import AzureCliCredential
        from openai import OpenAIError
    except ImportError as error:
        raise RuntimeError("Install infra/scripts/requirements-smoke.txt in a virtual environment before opting into inference.") from error

    run_id = uuid.uuid4().hex[:12]
    print(f"Smoke run {run_id}; UTC {datetime.now(timezone.utc).isoformat()}; synthetic prompt only.")
    try:
        with AzureCliCredential() as credential:
            with AIProjectClient(endpoint=config.project_endpoint, credential=credential, retry_total=0, connection_timeout=15, read_timeout=120) as project:
                exercise_agent(project, PromptAgentDefinition, config, run_id)
    except (AzureError, OpenAIError) as error:
        raise RuntimeError(f"Agent smoke failed ({type(error).__name__}). Check project permissions, Gateway.Invoke assignments and gateway telemetry. If creation timed out, inspect agents named launchpad-smoke-{run_id} for cleanup.") from error


def exercise_gateway(client, status_error: type[Exception]) -> None:
    for model, expected in [("unapproved-model", 403), ("embeddings", 400)]:
        try:
            client.chat.completions.create(model=model, messages=[{"role": "user", "content": "Synthetic authorization check."}])
        except status_error as error:
            if error.status_code != expected:
                raise RuntimeError(f"Gateway rejection for {model} returned {error.status_code}; expected {expected}.") from error
        else:
            raise RuntimeError(f"Gateway unexpectedly accepted {model} on the chat route.")
    for alias in sorted(CHAT_ALIASES):
        response = client.chat.completions.create(
            model=alias,
            messages=[{"role": "user", "content": f"Reply with exactly {EXPECTED_REPLY}."}],
            max_completion_tokens=2048,
        )
        if not response.choices or response.choices[0].finish_reason != "stop" or not isinstance(response.choices[0].message.content, str) or response.choices[0].message.content.strip() != EXPECTED_REPLY:
            raise RuntimeError(f"Gateway chat smoke failed for {alias}; response was incomplete or unexpected.")
        if response.usage is None or response.usage.total_tokens <= 0:
            raise RuntimeError(f"Gateway chat smoke for {alias} has no positive token usage.")
        print(f"PASS gateway chat alias: {alias}")
    response = client.embeddings.create(model="embeddings", input="Synthetic Launchpad readiness check.", encoding_format="float")
    if len(response.data) != 1 or len(response.data[0].embedding) != 3072 or not all(math.isfinite(value) for value in response.data[0].embedding):
        raise RuntimeError("Embedding response must contain one finite 3072-dimensional vector for the configured text-embedding-3-large default.")
    if response.usage.total_tokens <= 0:
        raise RuntimeError("Embedding response has no positive token usage.")
    print("PASS gateway embeddings alias: one 3072-dimensional vector, positive usage; model/operation rejections verified")


def run_gateway(config: Configuration, client_id: str) -> None:
    try:
        from azure.core.exceptions import AzureError
        from azure.identity import ManagedIdentityCredential, get_bearer_token_provider
        from openai import APIStatusError, OpenAI, OpenAIError
    except ImportError as error:
        raise RuntimeError("Install infra/scripts/requirements-smoke.txt before opting into inference.") from error
    print(f"Gateway smoke UTC {datetime.now(timezone.utc).isoformat()}; synthetic inputs only.")
    try:
        with ManagedIdentityCredential(client_id=client_id) as credential:
            provider = get_bearer_token_provider(credential, f"{config.gateway_audience}/.default")
            with OpenAI(base_url=config.gateway_url, api_key=provider, max_retries=0, timeout=120) as client:
                exercise_gateway(client, APIStatusError)
    except (AzureError, OpenAIError) as error:
        raise RuntimeError(f"Gateway smoke failed ({type(error).__name__}). Verify the runner has the selected runtime identity and its Gateway.Invoke assignment; inspect gateway telemetry.") from error


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True, help="Exported readiness output value; keep this environment-specific file uncommitted.")
    parser.add_argument("--use-case", required=True, help="Use case to verify, e.g. ai-app-01.")
    parser.add_argument("--allow-paid-inference", action="store_true", help="Explicitly authorize the selected synthetic agent or three-model gateway test; model usage incurs charges.")
    parser.add_argument("--agent-model", choices=sorted(CHAT_ALIASES), default="fast-chat", help="Chat alias for the temporary Foundry agent.")
    parser.add_argument("--gateway-runtime-client-id", help="Instead of creating an agent, test both chat aliases and embeddings through APIM using this runtime managed identity attached to the runner.")
    args = parser.parse_args(argv)
    if args.gateway_runtime_client_id and not args.allow_paid_inference:
        parser.error("--gateway-runtime-client-id requires --allow-paid-inference")
    try:
        config = load_configuration(args.config, args.use_case)
        config = replace(config, model=args.agent_model, agent_model=f"{config.connection_name}/{args.agent_model}")
        if args.gateway_runtime_client_id:
            uuid.UUID(args.gateway_runtime_client_id)
        preflight(config)
        if args.allow_paid_inference:
            if args.gateway_runtime_client_id:
                run_gateway(config, args.gateway_runtime_client_id)
            else:
                run_agent(config)
        else:
            print("PREFLIGHT ONLY: no agent created or model invoked. Agent-subnet connectivity, inference and telemetry remain unverified.")
        return 0
    except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired, http.client.HTTPException) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
