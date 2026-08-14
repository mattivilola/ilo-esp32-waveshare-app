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
        self.assertIn("#define WIFI_PROFILE_AUTH_FAILURES 2", TRANSPORT_SOURCE)
        self.assertIn("wifi_auth_failure_count >= WIFI_PROFILE_AUTH_FAILURES", TRANSPORT_SOURCE)
        self.assertIn("wifi_not_found_count >= 3", TRANSPORT_SOURCE)
        self.assertIn("wifi_auth_failure_count = 0", TRANSPORT_SOURCE)
        self.assertIn("wifi_not_found_count = 0", TRANSPORT_SOURCE)
        self.assertIn(
            "if (sheet_visible && (wifi_setup_connecting || wifi_setup_scan_paused))",
            UI_SOURCE,
        )

    def test_three_successful_networks_are_remembered_in_nvs(self):
        self.assertIn("#define WIFI_KNOWN_MAX 3", TRANSPORT_SOURCE)
        for key in (
            '"wifi_count"',
            '"wifi0_ssid"',
            '"wifi0_pwd"',
            '"wifi1_ssid"',
            '"wifi1_pwd"',
            '"wifi2_ssid"',
            '"wifi2_pwd"',
        ):
            self.assertIn(key, TRANSPORT_SOURCE)
        got_ip = TRANSPORT_SOURCE[
            TRANSPORT_SOURCE.index("IP_EVENT_STA_GOT_IP"):
            TRANSPORT_SOURCE.index("static esp_err_t nvs_read_string")
        ]
        self.assertIn("remember_current_wifi_network()", got_ip)
        update = TRANSPORT_SOURCE[
            TRANSPORT_SOURCE.index("bool mac_transport_update_wifi"):
            TRANSPORT_SOURCE.index("size_t mac_transport_scan_wifi")
        ]
        self.assertNotIn("nvs_set_str", update)
        self.assertIn("remembered after DHCP succeeds", update)

    def test_remembered_networks_are_unique_by_exact_ssid(self):
        promotion = TRANSPORT_SOURCE[
            TRANSPORT_SOURCE.index("static esp_err_t promote_known_wifi_network(const wifi_known_network_t *network)\n{"):
            TRANSPORT_SOURCE.index("static esp_err_t load_known_wifi_networks(const mac_transport_config_t *legacy_config)\n{")
        ]
        self.assertIn(
            "if (strcmp(previous[index].ssid, network->ssid) == 0) continue",
            promotion,
        )
        loader = TRANSPORT_SOURCE[
            TRANSPORT_SOURCE.index("static esp_err_t load_known_wifi_networks(const mac_transport_config_t *legacy_config)\n{"):
            TRANSPORT_SOURCE.index("static esp_err_t remember_current_wifi_network(void)\n{")
        ]
        self.assertIn("if (duplicate)", loader)
        self.assertIn("needs_rewrite = true", loader)
        self.assertIn("persist_known_wifi_networks()", loader)

    def test_existing_single_network_migrates_and_driver_storage_is_ram_only(self):
        self.assertIn("Migrated the existing Wi-Fi profile", TRANSPORT_SOURCE)
        self.assertIn('nvs_read_string(handle, "wifi_ssid"', TRANSPORT_SOURCE)
        self.assertIn('nvs_read_string(handle, "wifi_password"', TRANSPORT_SOURCE)
        self.assertIn("esp_wifi_restore()", TRANSPORT_SOURCE)
        self.assertIn("esp_wifi_set_storage(WIFI_STORAGE_RAM)", TRANSPORT_SOURCE)

    def test_recovery_rotates_remembered_profiles(self):
        self.assertIn("wifi_rotation_requested = true", TRANSPORT_SOURCE)
        self.assertIn("apply_next_known_wifi_network()", TRANSPORT_SOURCE)
        self.assertIn("Trying the next remembered Wi-Fi profile", TRANSPORT_SOURCE)
        self.assertIn(
            "wifi_known_network_count_snapshot > 1",
            TRANSPORT_SOURCE,
        )

    def test_setup_identifies_connects_and_forgets_saved_networks(self):
        self.assertIn('"%u/3 remembered / tap saved to connect / hold saved to forget"', UI_SOURCE)
        self.assertIn('"SAVED  %s"', UI_SOURCE)
        self.assertIn("LV_EVENT_LONG_PRESSED", UI_SOURCE)
        self.assertIn("wifi_forget_callback(forgotten_ssid)", UI_SOURCE)
        self.assertIn('wifi_selected_known ? "Connect" : "Save & connect"', UI_SOURCE)
        self.assertIn("saved only after Wi-Fi connects", UI_SOURCE)


if __name__ == "__main__":
    unittest.main()
