import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "firmware" / "components" / "ui" / "dashboard_ui.c").read_text()


class RebootControlSourceTests(unittest.TestCase):
    def test_board_reboot_requires_a_progressive_hold(self):
        handler = SOURCE[
            SOURCE.index("static void reboot_setting_tapped"):
            SOURCE.index("static void wifi_input_tapped")
        ]
        self.assertIn("REBOOT_ACTION_HOLD_MS 1500U", SOURCE)
        self.assertIn("LV_EVENT_PRESSING", handler)
        self.assertIn("lv_tick_elaps(reboot_hold_started_tick)", handler)
        self.assertIn("lv_bar_set_value", handler)
        self.assertIn("esp_restart()", handler)

    def test_settings_explains_the_hold_gesture(self):
        settings = SOURCE[
            SOURCE.index("static void build_settings_page"):
            SOURCE.index("static int active_page_index")
        ]
        self.assertIn('"Reboot board"', settings)
        self.assertIn('"HOLD 1.5 SEC"', settings)
        self.assertIn("settings_reboot_progress = lv_bar_create", settings)


if __name__ == "__main__":
    unittest.main()
