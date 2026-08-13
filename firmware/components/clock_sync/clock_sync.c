#include "clock_sync.h"

#include <sys/time.h>
#include <time.h>

#include "board_waveshare_5.h"
#include "esp_log.h"
#include "esp_netif_sntp.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "mac_transport.h"

#define CLOCK_READY_BIT BIT0
#define CLOCK_SYNC_TIMEOUT_MS 15000
#define CLOCK_RETRY_INTERVAL_MS 60000
#define MINIMUM_TRUSTED_EPOCH 1704067200LL // 2024-01-01 00:00:00 UTC

static const char *TAG = "clock_sync";
static EventGroupHandle_t clock_events;

static bool clock_is_valid(void)
{
    return time(NULL) >= MINIMUM_TRUSTED_EPOCH;
}

static bool restore_clock_from_rtc(void)
{
    int64_t rtc_epoch = 0;
    esp_err_t status = board_waveshare_5_rtc_read_epoch(&rtc_epoch);
    if (status != ESP_OK || rtc_epoch < MINIMUM_TRUSTED_EPOCH) {
        ESP_LOGI(TAG, "RTC has no trusted retained UTC yet");
        return false;
    }
    struct timeval restored = {
        .tv_sec = (time_t)rtc_epoch,
        .tv_usec = 0,
    };
    if (settimeofday(&restored, NULL) != 0 || !clock_is_valid()) {
        ESP_LOGW(TAG, "RTC UTC could not be applied to the system clock");
        return false;
    }
    ESP_LOGI(TAG, "System clock restored from battery-backed RTC");
    return true;
}

static bool sync_clock_from_network(void)
{
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
    time_t synchronized = time(NULL);
    status = board_waveshare_5_rtc_write_epoch((int64_t)synchronized);
    if (status == ESP_OK) {
        ESP_LOGI(TAG, "Battery-backed RTC updated from network UTC");
    } else {
        ESP_LOGW(TAG, "Network time is valid, but RTC update failed: %s", esp_err_to_name(status));
    }
    return true;
}

static void clock_task(void *argument)
{
    (void)argument;
    for (;;) {
        if (mac_transport_wait_for_network(30000) && sync_clock_from_network()) {
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
    if (clock_is_valid() || restore_clock_from_rtc()) {
        xEventGroupSetBits(clock_events, CLOCK_READY_BIT);
    }
    if (xTaskCreatePinnedToCore(clock_task, "clock_sync", 4096, NULL, 3, NULL, 0) != pdPASS) {
        if (!clock_is_valid()) {
            vEventGroupDelete(clock_events);
            clock_events = NULL;
            return false;
        }
        ESP_LOGW(TAG, "RTC time is available, but the SNTP refresh task could not start");
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
