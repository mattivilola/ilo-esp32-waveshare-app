import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "firmware" / "components" / "clock_sync" / "clock_sync.c").read_text()


class ClockSyncSourceTests(unittest.TestCase):
    def test_sntp_refresh_is_asynchronous_without_a_dedicated_worker(self):
        self.assertIn("config.wait_for_sync = false", SOURCE)
        self.assertIn("config.sync_cb = clock_synchronized", SOURCE)
        self.assertNotIn("xTaskCreate", SOURCE)
        self.assertNotIn("clock_task", SOURCE)

    def test_network_time_is_persisted_by_an_existing_caller(self):
        self.assertIn("rtc_update_pending = true", SOURCE)
        self.assertIn("persist_synchronized_clock();", SOURCE)
        self.assertIn("board_waveshare_5_rtc_write_epoch", SOURCE)


if __name__ == "__main__":
    unittest.main()
