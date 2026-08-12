#include "clock_sync.h"

#include <time.h>

#include "esp_log.h"
#include "esp_netif_sntp.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "mac_transport.h"

#define CLOCK_READY_BIT BIT0
#define CLOCK_SYNC_TIMEOUT_MS 15000
#define CLOCK_RETRY_INTERVAL_MS 60000

static const char *TAG = "clock_sync";
static EventGroupHandle_t clock_events;

static bool clock_is_valid(void)
{
    return time(NULL) > 1700000000;
}

static bool sync_clock(void)
{
    if (clock_is_valid()) return true;

    esp_sntp_config_t config = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
    esp_err_t status = esp_netif_sntp_init(&config);
    if (status != ESP_OK && status != ESP_ERR_INVALID_STATE) {
        ESP_LOGW(TAG, "Unable to initialize SNTP: %s", esp_err_to_name(status));
        return false;
    }
    status = esp_netif_sntp_sync_wait(pdMS_TO_TICKS(CLOCK_SYNC_TIMEOUT_MS));
    if (status != ESP_OK || !clock_is_valid()) {
        ESP_LOGW(TAG, "Time sync unavailable; retrying automatically");
        return false;
    }
    ESP_LOGI(TAG, "Clock synchronized over Wi-Fi");
    return true;
}

static void clock_task(void *argument)
{
    (void)argument;
    for (;;) {
        if (mac_transport_wait_for_network(30000) && sync_clock()) {
            xEventGroupSetBits(clock_events, CLOCK_READY_BIT);
            vTaskDelete(NULL);
        }
        vTaskDelay(pdMS_TO_TICKS(CLOCK_RETRY_INTERVAL_MS));
    }
}

bool clock_sync_start(void)
{
    if (clock_events != NULL) return true;
    clock_events = xEventGroupCreate();
    if (clock_events == NULL) return false;
    if (clock_is_valid()) {
        xEventGroupSetBits(clock_events, CLOCK_READY_BIT);
        return true;
    }
    if (xTaskCreatePinnedToCore(clock_task, "clock_sync", 4096, NULL, 3, NULL, 0) != pdPASS) {
        vEventGroupDelete(clock_events);
        clock_events = NULL;
        return false;
    }
    return true;
}

bool clock_sync_wait(uint32_t timeout_ms)
{
    if (clock_is_valid()) return true;
    if (clock_events == NULL) return false;
    EventBits_t bits = xEventGroupWaitBits(
        clock_events,
        CLOCK_READY_BIT,
        pdFALSE,
        pdTRUE,
        pdMS_TO_TICKS(timeout_ms)
    );
    return (bits & CLOCK_READY_BIT) != 0 && clock_is_valid();
}
