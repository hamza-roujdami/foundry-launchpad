"""Keep public entry points and the illustrated architecture in sync."""

import json
from pathlib import Path
import re
import struct
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).parents[2]


class DocumentationTests(unittest.TestCase):
    def test_local_readme_links_exist(self):
        files = [
            ROOT / "README.md", ROOT / "infra/README.md",
            ROOT / "infra/terraform/README.md", ROOT / "infra/bicep/README.md",
            *sorted((ROOT / "infra/terraform/modules").glob("*/README.md")),
        ]
        for file in files:
            for link in re.findall(r"\]\(([^)]+)\)", file.read_text()):
                target = link.split("#", 1)[0]
                if target and not re.match(r"[a-zA-Z]+:", target):
                    self.assertTrue((file.parent / target).exists(), f"{file.relative_to(ROOT)}: {link}")

    def test_primary_diagram_and_sources_match(self):
        readme = (ROOT / "README.md").read_text()
        self.assertIn("](docs/reference-architecture.png)", readme)
        self.assertIn("<summary>Mermaid architecture source</summary>", readme)
        svg_path = ROOT / "docs/reference-architecture.svg"
        svg_text = svg_path.read_text()
        svg = ET.fromstring(svg_text)
        png = (ROOT / "docs/reference-architecture.png").read_bytes()
        self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">II", png[16:24]), (int(svg.get("width")), int(svg.get("height"))))
        canvas = json.loads((ROOT / "docs/reference-architecture.canvas").read_text())
        groups = {node["label"] for node in canvas["nodes"] if node.get("label", "").startswith("rg-")}
        self.assertEqual(len(groups), 5)
        for group in groups:
            self.assertIn(group, readme)
            self.assertIn(group, svg_text)
        for alias in ("fast-chat", "advanced-chat", "embeddings"):
            self.assertIn(alias, readme)
            self.assertIn(alias, svg_text)
        self.assertNotIn("DESIGN PREVIEW", svg_text)
        self.assertNotIn("foundry-launchpad-architecture-preview", readme)

    def test_platform_scope_is_explicit(self):
        readme = (ROOT / "README.md").read_text()
        for text in ("application CI/CD", "Git/org setup", "Developer connectivity/access provisioning", "platform landing zone"):
            self.assertIn(text, readme)
        self.assertIn("source validation only", readme)


if __name__ == "__main__":
    unittest.main()
