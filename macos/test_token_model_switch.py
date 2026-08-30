import os
import tempfile
import unittest
from pathlib import Path

import TokenModelSwitch as app


class MacSwitchLogicTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.config_dir = self.root / ".codex"
        self.config_dir.mkdir()
        (self.config_dir / "auth.json").write_text("{}", encoding="utf-8")
        self.config = self.config_dir / "config.toml"
        self.config.write_text(
            'model_provider = "openai"\nmodel = "gpt-5.6-sol"\n\n'
            '[features]\nkeep = true\n',
            encoding="utf-8",
        )
        self.providers = self.root / "providers.json"
        self.providers.write_text(app.PROVIDERS_PATH.read_text(encoding="utf-8"), encoding="utf-8")
        (self.root / "deepseek-model-catalog.json").write_text(
            (app.PROVIDERS_PATH.parent / "deepseek-model-catalog.json").read_text(encoding="utf-8"),
            encoding="utf-8",
        )

    def tearDown(self):
        self.temp.cleanup()

    def test_honknet_rewrites_route_and_preserves_other_tables(self):
        old = os.environ.get("HONKNET_API_KEY")
        os.environ["HONKNET_API_KEY"] = "test-only"
        try:
            output = app.switched_config("honknet", self.config, self.providers)
        finally:
            if old is None:
                os.environ.pop("HONKNET_API_KEY", None)
            else:
                os.environ["HONKNET_API_KEY"] = old
        self.assertIn('model_provider = "honknet"', output)
        self.assertIn('[model_providers.honknet]', output)
        self.assertIn("[features]", output)
        self.assertIn("keep = true", output)

    def test_switch_creates_backup_before_replace(self):
        old = os.environ.get("HONKNET_API_KEY")
        os.environ["HONKNET_API_KEY"] = "test-only"
        try:
            backup = app.switch_provider("honknet", self.config, self.providers)
        finally:
            if old is None:
                os.environ.pop("HONKNET_API_KEY", None)
            else:
                os.environ["HONKNET_API_KEY"] = old
        self.assertTrue(backup.exists())
        self.assertIn('model_provider = "honknet"', self.config.read_text(encoding="utf-8"))
        self.assertIn('model_provider = "openai"', backup.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
