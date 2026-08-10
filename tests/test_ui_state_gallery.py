import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
GALLERY = ROOT / "docs" / "images" / "ui-states"
SCENARIOS = (
    "offline",
    "loading",
    "stale",
    "error",
    "long-text",
    "privacy",
    "sleep",
    "reconnect",
    "screensaver",
    "approval-request",
)


class UIStateGalleryTests(unittest.TestCase):
    def test_complete_gallery_is_exact_board_resolution(self) -> None:
        self.assertEqual(
            {path.stem for path in GALLERY.glob("*.png")},
            set(SCENARIOS),
        )

        for scenario in SCENARIOS:
            with self.subTest(scenario=scenario):
                payload = (GALLERY / f"{scenario}.png").read_bytes()
                self.assertEqual(payload[:8], b"\x89PNG\r\n\x1a\n")
                self.assertEqual(payload[12:16], b"IHDR")
                self.assertEqual(struct.unpack(">II", payload[16:24]), (1024, 600))


if __name__ == "__main__":
    unittest.main()
