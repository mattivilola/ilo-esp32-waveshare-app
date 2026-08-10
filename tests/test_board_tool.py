import importlib.util
from importlib.machinery import SourceFileLoader
import math
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
LOADER = SourceFileLoader("ilo_board_tool", str(ROOT / "tools" / "board"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
board = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(board)


class ProvisioningValidationTests(unittest.TestCase):
    def validate(self, latitude=60.1699, longitude=24.9384):
        board.validate_provisioning(
            "Home WiFi",
            "correct horse battery staple",
            "192.168.1.20",
            47472,
            "Helsinki",
            latitude,
            longitude,
        )

    def test_accepts_normal_weather_coordinates(self):
        self.validate()

    def test_rejects_out_of_range_weather_coordinates(self):
        with self.assertRaises(SystemExit):
            self.validate(latitude=90.1)
        with self.assertRaises(SystemExit):
            self.validate(longitude=-180.1)

    def test_rejects_non_finite_weather_coordinates(self):
        with self.assertRaises(SystemExit):
            self.validate(latitude=math.nan)
        with self.assertRaises(SystemExit):
            self.validate(longitude=math.inf)


class OTAPolicyTests(unittest.TestCase):
    def test_project_layout_has_two_equal_rollback_slots(self):
        layout = board.validate_ota_layout(ROOT / "firmware" / "partitions.csv")
        self.assertEqual(layout["slot_size"], 0x400000)
        self.assertEqual(layout["ota_0_offset"], 0x20000)
        self.assertEqual(layout["ota_1_offset"], 0x420000)

    def test_layout_rejects_factory_or_mismatched_slots(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "partitions.csv"
            path.write_text(
                "otadata,data,ota,0xf000,0x2000,\n"
                "factory,app,factory,0x20000,0x100000,\n"
                "ota_0,app,ota_0,0x120000,0x100000,\n"
                "ota_1,app,ota_1,0x220000,0x200000,\n"
            )
            with self.assertRaises(SystemExit):
                board.validate_ota_layout(path)

    def test_release_policy_requires_rollback_and_signed_updates(self):
        self.assertTrue(board.ota_release_policy_errors({}))
        safe = {
            "CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE": "y",
            "CONFIG_SECURE_SIGNED_APPS_NO_SECURE_BOOT": "y",
            "CONFIG_SECURE_SIGNED_ON_UPDATE_NO_SECURE_BOOT": "y",
            "CONFIG_SECURE_SIGNED_APPS_RSA_SCHEME": "y",
        }
        self.assertEqual(board.ota_release_policy_errors(safe), [])

    def test_private_key_is_refused_by_artifact_verifier(self):
        with tempfile.TemporaryDirectory() as directory:
            key = Path(directory) / "private.pem"
            key.write_text("-----BEGIN PRIVATE KEY-----\nnot-a-real-key\n-----END PRIVATE KEY-----\n")
            with self.assertRaises(SystemExit):
                board.public_verification_key(key)


if __name__ == "__main__":
    unittest.main()
