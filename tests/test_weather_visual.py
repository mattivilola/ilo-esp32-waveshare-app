from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
WEATHER_COMPONENT = ROOT / "firmware" / "components" / "weather_model"


class WeatherVisualTests(unittest.TestCase):
    def test_open_meteo_codes_have_stable_visual_groups_and_labels(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "weather_visual_test"
            subprocess.run(
                [
                    "cc",
                    "-std=c11",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-I",
                    str(WEATHER_COMPONENT / "include"),
                    str(ROOT / "tests" / "weather_visual_test.c"),
                    str(WEATHER_COMPONENT / "weather_visual.c"),
                    "-o",
                    str(executable),
                ],
                check=True,
                capture_output=True,
            )
            subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    unittest.main()
