import importlib.util
from pathlib import Path
import struct
import unittest


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "generate_lando_screensaver_asset.py"
SPEC = importlib.util.spec_from_file_location("generate_lando_screensaver_asset", SCRIPT)
ASSET = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(ASSET)


class LandoScreensaverAssetTests(unittest.TestCase):
    def test_hex_color_accepts_hash_and_plain_value(self):
        self.assertEqual(ASSET.parse_hex_color("#3A454C"), (58, 69, 76))
        self.assertEqual(ASSET.parse_hex_color("3a454c"), (58, 69, 76))

    def test_rgb565_composites_transparency_over_panel_background(self):
        background = (58, 69, 76)
        self.assertEqual(
            ASSET.composite_rgb565((255, 255, 255, 0), background),
            ASSET.composite_rgb565((*background, 255), background),
        )
        packed_white = struct.unpack("<H", ASSET.composite_rgb565((255, 255, 255, 255), background))[0]
        self.assertEqual(packed_white, 0xFFFF)

    def test_committed_asset_matches_declared_geometry(self):
        frame_count = sum(len(columns) for _, _, columns in ASSET.FRAME_GROUPS)
        expected_size = frame_count * ASSET.CELL_WIDTH * ASSET.CELL_HEIGHT * 2
        binary = ROOT / "firmware" / "components" / "ui" / "assets" / "lando_screensaver.rgb565"
        header = ROOT / "firmware" / "components" / "ui" / "assets" / "lando_screensaver_asset.h"
        preview = ROOT / "mac-service" / "Sources" / "BoardUIPrototype" / "Resources" / "lando_idle.png"
        self.assertTrue(binary.is_file())
        self.assertEqual(binary.stat().st_size, expected_size)
        self.assertEqual(
            binary.read_bytes()[:2],
            ASSET.composite_rgb565((0, 0, 0, 0), ASSET.parse_hex_color(ASSET.DEFAULT_BACKGROUND)),
        )
        self.assertIn(
            f"#define LANDO_SCREENSAVER_ASSET_BYTES {expected_size}",
            header.read_text(),
        )
        self.assertTrue(preview.is_file())
        self.assertEqual(preview.read_bytes()[16:24], struct.pack(">II", ASSET.CELL_WIDTH, ASSET.CELL_HEIGHT))


if __name__ == "__main__":
    unittest.main()
