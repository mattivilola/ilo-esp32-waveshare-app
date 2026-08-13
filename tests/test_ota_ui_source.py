import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "firmware" / "components" / "ui" / "dashboard_ui.c").read_text()


class OTAUISourceTests(unittest.TestCase):
    def test_active_update_states_suppress_screensaver_and_display_sleep(self):
        helper = SOURCE[SOURCE.index("static bool ota_update_is_active"):SOURCE.index("static void screensaver_timer")]
        for state in (
            "DASHBOARD_OTA_CHECKING",
            "DASHBOARD_OTA_DOWNLOADING",
            "DASHBOARD_OTA_VERIFYING",
            "DASHBOARD_OTA_REBOOTING",
        ):
            self.assertIn(state, helper)

        timer = SOURCE[SOURCE.index("static void screensaver_timer"):SOURCE.index("static lv_obj_t *create_focus_button")]
        self.assertIn("if (ota_update_is_active())", timer)
        self.assertIn("lv_display_trigger_activity(ui_display)", timer)
        self.assertIn("board_waveshare_5_set_backlight(true)", timer)
        self.assertIn("lv_obj_add_flag(screensaver, LV_OBJ_FLAG_HIDDEN)", timer)

    def test_status_transition_wakes_the_display_immediately(self):
        setter = SOURCE[SOURCE.index("void dashboard_ui_set_ota_status"):SOURCE.index("void dashboard_ui_set_wifi_update_callback")]
        self.assertIn("if (ota_update_is_active())", setter)
        self.assertIn("lv_display_trigger_activity(ui_display)", setter)
        self.assertIn("board_waveshare_5_set_backlight(true)", setter)

    def test_install_transition_has_an_explicit_starting_state(self):
        labels = SOURCE[SOURCE.index("static void refresh_settings_labels"):SOURCE.index("static void ota_setting_tapped")]
        self.assertIn('"STARTING..."', labels)
        self.assertIn('"Preparing secure download / keep power connected"', labels)


if __name__ == "__main__":
    unittest.main()
