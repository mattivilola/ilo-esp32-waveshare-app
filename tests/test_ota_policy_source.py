import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
POLICY = (ROOT / "firmware" / "components" / "ota_policy" / "ota_policy.c").read_text()
UPDATER = (ROOT / "firmware" / "components" / "ota_updater" / "ota_updater.c").read_text()
MAIN = (ROOT / "firmware" / "main" / "main.cpp").read_text()


class OTAPolicySourceTests(unittest.TestCase):
    def test_confirmation_reuses_reserved_updater_worker(self):
        self.assertNotIn("xTaskCreate", POLICY)
        self.assertNotIn("validation_task", POLICY)
        self.assertNotIn("ota_policy_confirm_after_stability", MAIN)
        self.assertIn("ota_policy_confirmation_required()", UPDATER)
        self.assertIn("ota_policy_confirm_pending_image()", UPDATER)
        self.assertIn("CONFIG_ILO_OTA_VALIDATION_SECONDS * 1000U", UPDATER)
        self.assertIn("OTA_UPDATER_VERIFYING", UPDATER)
        self.assertIn("Completing first-boot health check", UPDATER)

    def test_confirmation_logs_heap_and_keeps_persistent_validity_gates(self):
        self.assertIn("heap_caps_get_free_size", POLICY)
        self.assertNotIn("CONFIG_ILO_OTA_MIN_INTERNAL_HEAP", POLICY)
        self.assertNotIn("free_internal <", POLICY)
        self.assertIn("ESP_OTA_IMG_PENDING_VERIFY", POLICY)
        self.assertIn("esp_ota_mark_app_valid_cancel_rollback", POLICY)
        self.assertIn("esp_ota_mark_app_invalid_rollback_and_reboot", POLICY)


if __name__ == "__main__":
    unittest.main()
