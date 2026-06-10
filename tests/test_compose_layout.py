from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]


class ComposeLayoutTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.compose = yaml.safe_load((ROOT / "compose.yaml").read_text(encoding="utf-8"))
        cls.services = cls.compose.get("services", {})
        cls.volumes = cls.compose.get("volumes", {})

    def test_root_compose_only_runs_supporting_services(self) -> None:
        self.assertEqual(
            {"valkey", "qdrant", "ollama", "ollama-pull-all-minilm", "cap"},
            set(self.services),
        )
        for service in self.services.values():
            self.assertNotIn("build", service)

    def test_removed_legacy_caddy_and_backend_entrypoints(self) -> None:
        self.assertNotIn("caddy", self.services)
        self.assertNotIn("backend", self.services)
        self.assertNotIn("caddy-data", self.volumes)
        self.assertNotIn("caddy-config", self.volumes)
        self.assertFalse((ROOT / "Caddyfile").exists())
        self.assertFalse((ROOT / "Dockerfile.caddy").exists())

    def test_only_local_supporting_ports_are_published(self) -> None:
        published = {
            str(port)
            for service in self.services.values()
            for port in service.get("ports", [])
        }
        self.assertEqual(
            {
                "${QDRANT_HTTP_PORT:-127.0.0.1:6333}:6333",
                "${QDRANT_GRPC_PORT:-127.0.0.1:6334}:6334",
                "${OLLAMA_PORT:-127.0.0.1:11434}:11434",
                "127.0.0.1:3000:3000",
            },
            published,
        )

    def test_ollama_embedding_model_pull_is_explicit(self) -> None:
        pull = self.services["ollama-pull-all-minilm"]
        self.assertEqual(["pull", "${OLLAMA_EMBEDDING_MODEL:-all-minilm}"], pull["command"])
        self.assertEqual("http://ollama:11434", pull["environment"]["OLLAMA_HOST"])


if __name__ == "__main__":
    unittest.main()
