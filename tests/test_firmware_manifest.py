import base64
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("firmware_manifest", ROOT / "tools" / "firmware_manifest.py")
manifest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(manifest)


class FirmwareManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.keys = tempfile.TemporaryDirectory()
        cls.private_key = Path(cls.keys.name) / "private.pem"
        cls.public_key = Path(cls.keys.name) / "public.pem"
        subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:3072", "-out", cls.private_key], check=True, capture_output=True)
        subprocess.run(["openssl", "pkey", "-in", cls.private_key, "-pubout", "-out", cls.public_key], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.keys.cleanup()

    def create(self, directory: str):
        image = Path(directory) / "ILOBoardFirmware-0.2.0.bin"
        image.write_bytes(b"signed-image-fixture")
        output = Path(directory) / "manifest-v1.json"
        payload = manifest.create_manifest(
            image=image,
            private_key=self.private_key,
            public_key=self.public_key,
            output=output,
            version="0.2.0",
            sequence=2,
            minimum_updater_version="0.2.0",
            release_notes=["Adds signed OTA delivery."],
            published_at="2026-08-12T10:00:00Z",
        )
        return output, payload

    def test_round_trip_is_signed_canonical_and_board_specific(self):
        with tempfile.TemporaryDirectory() as directory:
            output, created = self.create(directory)
            verified = manifest.load_and_validate_envelope(output, self.public_key)
            self.assertEqual(verified, created)
            self.assertEqual(verified["target"], manifest.BOARD_TARGET)
            self.assertEqual(verified["artifact"]["url"], manifest.RELEASE_URL_PREFIX + "ILOBoardFirmware-0.2.0.bin")

    def test_tampered_payload_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output, _ = self.create(directory)
            envelope = json.loads(output.read_text())
            payload = json.loads(base64.b64decode(envelope["payload"]))
            payload["version"] = "0.2.1"
            envelope["payload"] = base64.b64encode(manifest.canonical_payload(payload)).decode()
            output.write_text(json.dumps(envelope))
            with self.assertRaises(manifest.ManifestError):
                manifest.load_and_validate_envelope(output, self.public_key)

    def test_wrong_target_mutable_url_and_unknown_fields_are_rejected(self):
        valid = {
            "schema": manifest.PAYLOAD_SCHEMA,
            "target": manifest.BOARD_TARGET,
            "channel": "stable",
            "version": "0.2.0",
            "sequence": 2,
            "publishedAt": "2026-08-12T10:00:00Z",
            "minimumUpdaterVersion": "0.2.0",
            "artifact": {
                "url": manifest.RELEASE_URL_PREFIX + "ILOBoardFirmware-0.2.0.bin",
                "size": 123,
                "sha256": "a" * 64,
            },
            "releaseNotes": ["Safe updater."],
        }
        for mutate in (
            lambda value: value.update(target="another-board"),
            lambda value: value["artifact"].update(url="https://example.com/latest.bin"),
            lambda value: value.update(extra=True),
        ):
            candidate = copy.deepcopy(valid)
            mutate(candidate)
            with self.assertRaises(manifest.ManifestError):
                manifest.validate_payload(candidate)

    def test_private_or_wrong_size_public_key_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            private_copy = Path(directory) / "private.pem"
            private_copy.write_bytes(self.private_key.read_bytes())
            with self.assertRaises(manifest.ManifestError):
                manifest.public_key_id(private_copy)
            small_private = Path(directory) / "small-private.pem"
            small_public = Path(directory) / "small-public.pem"
            subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", small_private], check=True, capture_output=True)
            subprocess.run(["openssl", "pkey", "-in", small_private, "-pubout", "-out", small_public], check=True, capture_output=True)
            with self.assertRaises(manifest.ManifestError):
                manifest.public_key_id(small_public)


if __name__ == "__main__":
    unittest.main()
