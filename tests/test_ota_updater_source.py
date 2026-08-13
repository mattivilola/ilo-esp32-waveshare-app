import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "firmware" / "components" / "ota_updater" / "ota_updater.c").read_text()


class OTAUpdaterSourceTests(unittest.TestCase):
    def test_worker_uses_a_static_stack_and_explicit_ready_state(self):
        self.assertIn("static StackType_t updater_task_stack", SOURCE)
        self.assertIn("xTaskCreateStatic(", SOURCE)
        self.assertNotRegex(SOURCE, re.compile(r"xTaskCreate\(updater_task"))
        self.assertIn("updater_ready = true;", SOURCE)
        self.assertIn("!updater_ready || updater_task_handle == NULL", SOURCE)

    def test_partial_startup_is_cleaned_up_before_retry_is_allowed(self):
        self.assertIn("esp_event_handler_unregister(IP_EVENT", SOURCE)
        self.assertIn("esp_event_handler_unregister(WIFI_EVENT", SOURCE)
        self.assertIn("vEventGroupDelete(network_events)", SOURCE)
        self.assertIn("vEventGroupDelete(commands)", SOURCE)
        self.assertIn("commands = NULL;", SOURCE)
        self.assertIn("network_events = NULL;", SOURCE)

    def test_manifest_check_reports_each_bounded_failure_stage(self):
        self.assertIn("Wi-Fi unavailable for update check", SOURCE)
        self.assertIn("Clock unavailable for secure update check", SOURCE)
        self.assertIn("Update manifest was not verified", SOURCE)
        self.assertIn("Verified signed manifest for %s", SOURCE)


if __name__ == "__main__":
    unittest.main()
