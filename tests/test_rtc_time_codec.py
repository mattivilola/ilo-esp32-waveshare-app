from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BOARD_COMPONENT = ROOT / "firmware" / "components" / "board_waveshare_5"


class RTCTimeCodecTests(unittest.TestCase):
    def test_codec_rejects_untrusted_values_and_round_trips_utc(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "rtc_time_codec_test"
            subprocess.run(
                [
                    "cc",
                    "-std=c11",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-I",
                    str(BOARD_COMPONENT / "include"),
                    str(ROOT / "tests" / "rtc_time_codec_test.c"),
                    str(BOARD_COMPONENT / "rtc_time_codec.c"),
                    "-o",
                    str(executable),
                ],
                check=True,
                capture_output=True,
            )
            subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    unittest.main()
