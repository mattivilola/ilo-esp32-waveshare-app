import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
UI_SOURCE = (ROOT / "firmware" / "components" / "ui" / "dashboard_ui.c").read_text()
TRANSPORT_SOURCE = (
    ROOT / "firmware" / "components" / "transport" / "mac_transport.c"
).read_text()


class WiFiSetupSourceTests(unittest.TestCase):
    def test_save_enters_a_single_visible_connection_attempt(self):
        action = UI_SOURCE[
            UI_SOURCE.index("static void wifi_setup_action"):
            UI_SOURCE.index("static void wifi_setup_tapped")
        ]
        self.assertIn("if (wifi_setup_connecting) return", action)
        self.assertIn("wifi_setup_set_inputs_enabled(false)", action)
        self.assertIn('"Connecting..."', action)
        self.assertIn('"Connecting to Wi-Fi"', action)
        self.assertIn('"Authenticating and requesting an address..."', action)

    def test_connection_result_is_explicit_and_success_closes_automatically(self):
        setter = UI_SOURCE[UI_SOURCE.index("void dashboard_ui_set_wifi_connection_state"):]
        self.assertIn("DASHBOARD_WIFI_CONNECTED", setter)
        self.assertIn('"Wi-Fi connected successfully"', setter)
        self.assertIn('"Wrong password or authentication failed"', setter)
        self.assertIn('"Network not found - check that the hotspot is on"', setter)
        self.assertIn("wifi_setup_close_pending = true", setter)
        self.assertIn("WIFI_CONNECTED_HOLD_MS", UI_SOURCE)

    def test_connection_attempt_pauses_disruptive_background_scans(self):
        refresh = UI_SOURCE[
            UI_SOURCE.index("static void wifi_scan_refresh"):
            UI_SOURCE.index("static void wifi_network_tapped")
        ]
        self.assertIn(
            "if (wifi_setup_connecting || wifi_setup_close_pending || wifi_setup_scan_paused) return",
            refresh,
        )

    def test_back_replaces_misleading_cancel_action(self):
        builder = UI_SOURCE[
            UI_SOURCE.index("static void build_wifi_setup"):
            UI_SOURCE.index("static lv_obj_t *create_setting_row")
        ]
        self.assertIn('create_label(back, "Back"', builder)
        self.assertNotIn('create_label(cancel, "Cancel"', builder)

    def test_transport_reports_real_wifi_results_to_the_ui(self):
        self.assertIn(
            "dashboard_ui_set_wifi_connection_state(DASHBOARD_WIFI_CONNECTING)",
            TRANSPORT_SOURCE,
        )
        self.assertIn(
            "dashboard_ui_set_wifi_connection_state(DASHBOARD_WIFI_CONNECTED)",
            TRANSPORT_SOURCE,
        )
        for state in (
            "DASHBOARD_WIFI_RETRYING",
            "DASHBOARD_WIFI_AUTH_FAILED",
            "DASHBOARD_WIFI_NOT_FOUND",
        ):
            self.assertIn(state, TRANSPORT_SOURCE)
        self.assertIn("dashboard_ui_set_wifi_connection_state(state)", TRANSPORT_SOURCE)

    def test_transient_hotspot_failures_retry_before_showing_terminal_errors(self):
        self.assertIn("wifi_auth_failure_count >= 2", TRANSPORT_SOURCE)
        self.assertIn("wifi_not_found_count >= 3", TRANSPORT_SOURCE)
        self.assertIn("wifi_auth_failure_count = 0", TRANSPORT_SOURCE)
        self.assertIn("wifi_not_found_count = 0", TRANSPORT_SOURCE)
        self.assertIn(
            "if (sheet_visible && (wifi_setup_connecting || wifi_setup_scan_paused))",
            UI_SOURCE,
        )


if __name__ == "__main__":
    unittest.main()
