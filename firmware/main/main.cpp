#include "esp_log.h"
#include "esp_timer.h"
#include "nvs_flash.h"

#include "board_waveshare_5.h"
#include "clock_sync.h"
#include "dashboard_model.h"
#include "dashboard_ui.h"
#include "focus_session.h"
#include "mac_transport.h"
#include "ota_policy.h"
#include "ota_updater.h"
#include "weather_client.h"

static const char *TAG = "ilo_board";

static void handle_ota_status(const ota_updater_status_t *status)
{
    if (status == nullptr) return;
    dashboard_ui_set_ota_status(
        static_cast<dashboard_ota_state_t>(status->state),
        status->available_version,
        status->progress_percent
    );
    mac_transport_publish_ota_status(status);
}

static void handle_mac_model(const dashboard_model_t *model)
{
    if (model != nullptr && model->weather_location_available) {
        weather_client_update_location(
            model->weather_location_name,
            model->weather_latitude,
            model->weather_longitude
        );
    }
    dashboard_ui_set_model(model);
}

extern "C" void app_main()
{
    int64_t startup_begin_us = esp_timer_get_time();
    esp_err_t nvs_status = nvs_flash_init();
    if (nvs_status == ESP_ERR_NVS_NO_FREE_PAGES || nvs_status == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ESP_ERROR_CHECK(nvs_flash_init());
    } else {
        ESP_ERROR_CHECK(nvs_status);
    }

    ESP_ERROR_CHECK(ota_policy_begin());

    ESP_LOGI(TAG, "Starting ILO Board protocol v1 (fixed Codex continue only)");
    ESP_ERROR_CHECK(board_waveshare_5_init());
    ESP_ERROR_CHECK(focus_session_init());
    ESP_ERROR_CHECK(dashboard_ui_init(board_waveshare_5_lcd()));
    dashboard_ui_set_x_news_refresh_callback(mac_transport_request_x_news_refresh);
    dashboard_ui_set_wifi_update_callback(mac_transport_update_wifi);
    dashboard_ui_set_wifi_scan_callback(mac_transport_scan_wifi);
    dashboard_ui_set_wifi_known_callbacks(mac_transport_known_wifi, mac_transport_forget_wifi);
    dashboard_ui_set_codex_chat_callback(mac_transport_request_codex_chat);
    dashboard_ui_set_codex_action_callback(mac_transport_request_codex_action);
    dashboard_ui_set_focus_completion_callback(mac_transport_publish_focus_completion);
    dashboard_ui_set_ota_callbacks(ota_updater_request_check, ota_updater_request_install);

    // The dashboard model includes the bounded X News post cache and is much
    // larger than the main task stack. Keep the empty startup snapshot in
    // read-only firmware storage so model growth cannot corrupt the stack.
    static const dashboard_model_t initial = {};
    dashboard_ui_set_model(&initial);
    ESP_ERROR_CHECK(dashboard_ui_present_boot());
    ESP_LOGI(TAG, "First interactive frame presented after %lld ms",
             (long long)((esp_timer_get_time() - startup_begin_us) / 1000));
    // Reserve the weather worker's internal stack before Wi-Fi/TLS fragment
    // the remaining DMA-capable RAM. The worker waits for network readiness.
    if (!weather_client_start(dashboard_ui_set_weather)) {
        ESP_LOGW(TAG, "Weather client could not be started");
    }

    if (!mac_transport_start(handle_mac_model)) {
        bool wifi_started = mac_transport_start_wifi_only();
        ESP_LOGW(TAG, "Mac host is not configured; keeping the standalone dashboard");
        dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_NOT_CONFIGURED);
        if (wifi_started && !clock_sync_start()) {
            ESP_LOGW(TAG, "Clock synchronization could not be started");
        }
    } else {
        if (!clock_sync_start()) {
            ESP_LOGW(TAG, "Clock synchronization could not be started");
        }
    }
    (void)ota_updater_start(handle_ota_status);
}
