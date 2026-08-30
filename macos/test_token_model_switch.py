import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

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

    def test_honknet_quota_parser_uses_public_usage_shape(self):
        old = os.environ.get("HONKNET_API_KEY")
        os.environ["HONKNET_API_KEY"] = "test-only"
        try:
            with patch.object(app, "_json_request", return_value={
                "valid": True,
                "quota": {"remaining_usd": 12.5, "unit": "USD"},
                "usage": {"today": {"requests": 3, "total_tokens": 456}},
            }):
                result = app.query_honknet_usage()
        finally:
            if old is None:
                os.environ.pop("HONKNET_API_KEY", None)
            else:
                os.environ["HONKNET_API_KEY"] = old
        self.assertEqual(result["value"], "12.50 USD")
        self.assertIn("3 requests", result["detail"])
        self.assertEqual(result["status"], "Available")

    def test_deepseek_balance_parser_prefers_cny(self):
        old = os.environ.get("DEEPSEEK_API_KEY")
        os.environ["DEEPSEEK_API_KEY"] = "test-only"
        try:
            with patch.object(app, "_json_request", return_value={
                "is_available": True,
                "balance_infos": [
                    {"currency": "USD", "total_balance": "1"},
                    {"currency": "CNY", "total_balance": "28.14", "topped_up_balance": "20", "granted_balance": "8.14"},
                ],
            }):
                result = app.query_deepseek_balance()
        finally:
            if old is None:
                os.environ.pop("DEEPSEEK_API_KEY", None)
            else:
                os.environ["DEEPSEEK_API_KEY"] = old
        self.assertEqual(result["value"], "28.14 CNY")
        self.assertIn("Topped up  20.00 CNY", result["detail"])
        self.assertEqual(result["status"], "Available")


if __name__ == "__main__":
    unittest.main()
