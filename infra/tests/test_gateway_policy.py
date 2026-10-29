"""Execute the actual policy expressions offline; this is not an APIM runtime emulator."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).parents[2]


class GatewayPolicyTests(unittest.TestCase):
    def setUp(self):
        source = (ROOT / "infra/bicep/policies/gateway.xml").read_text()
        self.policy = ET.fromstring(source)

    def test_embedding_policy_is_separate_from_chat(self):
        inbound = self.policy.find("inbound")
        parents = {child: parent for parent in self.policy.iter() for child in parent}
        limit = inbound.find(".//rate-limit-by-key")
        self.assertIn('== "embeddings-create"', parents[limit].get("condition"))
        self.assertEqual(limit.get("calls"), "__EMBEDDING_REQUESTS_PER_MINUTE__")
        self.assertIn("embeddings:", limit.get("counter-key"))
        token_limit = inbound.find(".//llm-token-limit")
        self.assertIn('!= "embeddings-create"', parents[token_limit].get("condition"))
        safety = inbound.find(".//llm-content-safety")
        self.assertNotIn("embeddings", parents[safety].get("condition"))
        self.assertEqual(safety.get("shield-prompt"), "true")
        self.assertEqual({c.get("threshold") for c in safety.findall("./categories/category")}, {"4"})
        self.assertEqual(self.policy.find("./outbound//emit-metric").get("name"), "EmbeddingTokens")
        self.assertIsNotNone(self.policy.find("./outbound//trace[@severity='error']"))
        text = ET.tostring(inbound, encoding="unicode")
        self.assertLess(text.index("validate-jwt"), text.index('name="modelValidation"'))
        self.assertLess(text.index('name="modelValidation"'), text.index("llm-content-safety"))

    def test_policy_parity(self):
        def canonical(source):
            source = re.sub(r"%\{.*?\}", "", source)
            source = source.replace("As<string>", "As&lt;string&gt;")
            for old, new in {
                "${tenant_id}": "__TENANT_ID__", "${client_id}": "__CLIENT_ID__",
                "${role}": "Gateway.Invoke", "${backend_url}": "__BACKEND_URL__",
                "${tokens_per_minute}": "__TOKENS_PER_MINUTE__",
                "${embedding_requests_per_minute}": "__EMBEDDING_REQUESTS_PER_MINUTE__",
            }.items():
                source = source.replace(old, new)
            def node(element):
                return element.tag, element.attrib, " ".join((element.text or "").split()), tuple(node(child) for child in element)
            return node(ET.fromstring(source))
        terraform = (ROOT / "infra/terraform/modules/ai-hub-services/gateway-policy.xml.tftpl").read_text()
        bicep = (ROOT / "infra/bicep/policies/gateway.xml").read_text()
        self.assertEqual(canonical(terraform), canonical(bicep))

    @unittest.skipUnless(shutil.which("dotnet"), ".NET SDK required to execute C# policy expressions")
    def test_actual_csharp_expressions(self):
        model = self.policy.find(".//set-variable[@name='modelValidation']").get("value")[1:]
        tokens = self.policy.find(".//set-variable[@name='embeddingTokens']").get("value")[1:]
        ownership = next(
            element.get("condition")[1:] for element in self.policy.findall(".//when")
            if "stored.Body" in element.get("condition", "")
        )
        chat = next(
            element.text.strip()[1:] for element in self.policy.findall(".//set-body")
            if "reasoning_effort" in (element.text or "")
        )
        program = '''
using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

class Body {
    public string Json;
    public Body(string json) { Json = json; }
    public T As<T>(bool preserveContent = false) => (T)(object)JObject.Parse(Json);
}
interface IResponse { int StatusCode { get; } Body Body { get; } }
class Response : IResponse {
    public int StatusCode { get; set; } = 200;
    public Body Body { get; set; } = new Body("{}");
}
class Variables : Dictionary<string, object> {
    public T GetValueOrDefault<T>(string key) => TryGetValue(key, out var value) ? (T)value : default(T);
}
class Operation { public string Id = "chat-completions-create"; }
class Request { public Body Body = new Body("{}"); }
class Context {
    public Request Request = new Request();
    public Operation Operation = new Operation();
    public Variables Variables = new Variables();
    public Response Response = new Response();
}
class Program {
    static int checks;
    static void Check(bool value, string label) {
        checks++;
        if (!value) throw new Exception(label);
    }
    static void Main() {
        var context = new Context();
        Func<string> validate = () => __MODEL__;
        Func<double> usage = () => __TOKENS__;
        Func<bool> foreign = () => __OWNERSHIP__;
        Func<string> defaults = () => __CHAT__;
        foreach (var operation in new[] {"chat-completions-create", "responses-create", "embeddings-create"}) {
            context.Operation.Id = operation;
            foreach (var alias in new[] {"fast-chat", "advanced-chat", "embeddings"}) {
                context.Request.Body = new Body(new JObject { ["model"] = alias }.ToString());
                string expected = (operation == "embeddings-create") == (alias == "embeddings") ? "allowed" : "wrong-operation";
                Check(validate() == expected, operation + ":" + alias);
            }
            foreach (var alias in new[] {"gpt-6.1-sol", "gpt-6.1-terra", "text-embedding-3-large", "other", "fast-chat ", "FAST-CHAT"}) {
                context.Request.Body = new Body(new JObject { ["model"] = alias }.ToString());
                Check(validate() == "denied", "unapproved model");
            }
            foreach (var body in new[] {"{}", "null", "[]", "{", "{\\"model\\":null}", "{\\"model\\":1}", "{\\"model\\":[]}", "{\\"model\\":\\"\\"}", "{\\"model\\":\\" \\"}"}) {
                context.Request.Body = new Body(body);
                Check(validate() == "invalid", "invalid body");
            }
        }
        foreach (var alias in new[] {"fast-chat", "advanced-chat"}) {
            context.Variables["modelAlias"] = alias;
            context.Request.Body = new Body(new JObject { ["model"] = alias }.ToString());
            Check((string)JObject.Parse(defaults())["reasoning_effort"] == (alias == "fast-chat" ? "low" : "high"), "reasoning default");
            context.Request.Body = new Body(new JObject { ["model"] = alias, ["reasoning_effort"] = "medium" }.ToString());
            Check((string)JObject.Parse(defaults())["reasoning_effort"] == "medium", "explicit reasoning preserved");
        }
        context.Variables["caller"] = "caller-one";
        foreach (var alias in new[] {"fast-chat", "advanced-chat", "embeddings", "other"}) {
            var stored = new Response { Body = new Body(new JObject {
                ["metadata"] = new JObject { ["gateway_caller"] = "caller-one", ["gateway_model"] = alias }
            }.ToString()) };
            context.Variables["storedResponse"] = stored;
            Check(foreign() == (alias != "fast-chat" && alias != "advanced-chat"), "stored model ownership");
        }
        foreach (var body in new[] {"{}", "{", "{\\"metadata\\":{\\"gateway_caller\\":\\"caller-two\\",\\"gateway_model\\":\\"fast-chat\\"}}"}) {
            context.Variables["storedResponse"] = new Response { Body = new Body(body) };
            Check(foreign(), "foreign or untagged response denied");
        }
        context.Variables["storedResponse"] = new Response { StatusCode = 404 };
        Check(foreign(), "missing response denied");
        context.Variables.Remove("storedResponse");
        Check(foreign(), "null response denied");
        foreach (var body in new[] {"{}", "{", "{\\"usage\\":{\\"total_tokens\\":\\"5\\"}}", "{\\"usage\\":{\\"total_tokens\\":null}}"}) {
            context.Response.Body = new Body(body);
            Check(usage() < 0, "missing usage must not become zero");
        }
        context.Response.Body = new Body("{\\"usage\\":{\\"total_tokens\\":42},\\"data\\":[1,2,3]}");
        Check(usage() == 42, "embedding usage");
        Check(context.Response.Body.As<JObject>()["data"].Count() == 3, "response preserved");
        Console.WriteLine($"PASS {checks} actual policy expression cases");
    }
}
'''
        program = program.replace("using System;", "using System;\nusing System.Linq;")
        program = program.replace("__MODEL__", model).replace("__TOKENS__", tokens).replace("__OWNERSHIP__", ownership).replace("__CHAT__", chat)
        project = """<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework></PropertyGroup>
  <ItemGroup><Reference Include="Newtonsoft.Json"><HintPath>$(MSBuildSDKsPath)/../Newtonsoft.Json.dll</HintPath></Reference></ItemGroup>
</Project>"""
        with tempfile.TemporaryDirectory(prefix="launchpad-policy-") as directory:
            path = Path(directory)
            (path / "policy.csproj").write_text(project)
            (path / "Program.cs").write_text(program)
            (path / "NuGet.Config").write_text("<configuration><packageSources><clear /></packageSources></configuration>")
            environment = {**os.environ, "DOTNET_CLI_TELEMETRY_OPTOUT": "1", "DOTNET_NOLOGO": "1"}
            result = subprocess.run(["dotnet", "run", "--project", str(path / "policy.csproj")], capture_output=True, text=True, timeout=120, env=environment)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertRegex(result.stdout, r"PASS \d+ actual policy expression cases")


if __name__ == "__main__":
    unittest.main()
