import importlib.util
from importlib.machinery import SourceFileLoader
import math
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
