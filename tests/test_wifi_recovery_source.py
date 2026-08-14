import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "firmware" / "components" / "transport" / "mac_transport.c").read_text()


class WiFiRecoverySourceTests(unittest.TestCase):
    def test_late_hotspot_recovery_keeps_retrying_with_bounded_backoff(self):
        self.assertIn("wifi_recovery_task", SOURCE)
        self.assertIn("WIFI_RECONNECT_INITIAL_MS 1000", SOURCE)
        self.assertIn("WIFI_RECONNECT_MAX_MS 15000", SOURCE)
        self.assertIn("ulTaskNotifyTake", SOURCE)
        self.assertIn("esp_wifi_connect()", SOURCE)

    def test_disconnect_records_reason_and_wakes_recovery_worker(self):
        self.assertIn("wifi_event_sta_disconnected_t", SOURCE)
        self.assertIn("recovery remains active", SOURCE)
        self.assertIn("request_wifi_recovery();", SOURCE)


if __name__ == "__main__":
    unittest.main()
