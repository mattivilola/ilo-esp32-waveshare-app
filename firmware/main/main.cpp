#include "esp_log.h"
#include "nvs_flash.h"

#include "board_waveshare_5.h"
#include "dashboard_model.h"
#include "dashboard_ui.h"
#include "mac_transport.h"
#include "ota_policy.h"
#include "weather_client.h"

static const char *TAG = "ilo_board";

extern "C" void app_main()
{
    esp_err_t nvs_status = nvs_flash_init();
    if (nvs_status == ESP_ERR_NVS_NO_FREE_PAGES || nvs_status == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ESP_ERROR_CHECK(nvs_flash_init());
    } else {
        ESP_ERROR_CHECK(nvs_status);
    }

    ESP_ERROR_CHECK(ota_policy_begin());

    ESP_LOGI(TAG, "Starting ILO Board protocol v1 (read-only)");
    ESP_ERROR_CHECK(board_waveshare_5_init());
    ESP_ERROR_CHECK(dashboard_ui_init(board_waveshare_5_lcd()));
    ESP_ERROR_CHECK(ota_policy_confirm_after_stability());

    dashboard_model_t initial = dashboard_model_demo();
    dashboard_ui_set_model(&initial);

    if (!mac_transport_start(dashboard_ui_set_model)) {
        ESP_LOGW(TAG, "Wireless host is not configured; keeping the offline demo snapshot");
        dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_NOT_CONFIGURED);
    } else if (!weather_client_start(dashboard_ui_set_weather)) {
        ESP_LOGW(TAG, "Direct weather is not configured yet");
    }
}
