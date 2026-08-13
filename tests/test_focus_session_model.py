from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FOCUS_COMPONENT = ROOT / "firmware" / "components" / "focus_session"


class FocusSessionModelTests(unittest.TestCase):
    def test_deadline_pause_resume_extension_and_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "focus_session_model_test"
            subprocess.run(
                [
                    "cc",
                    "-std=c11",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-I",
                    str(FOCUS_COMPONENT / "include"),
                    str(ROOT / "tests" / "focus_session_model_test.c"),
                    str(FOCUS_COMPONENT / "focus_session_model.c"),
                    "-o",
                    str(executable),
                ],
                check=True,
                capture_output=True,
            )
            subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    unittest.main()
