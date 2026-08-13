#include "clock_sync.h"

#include <sys/time.h>
#include <time.h>

#include "board_waveshare_5.h"
#include "esp_log.h"
#include "esp_netif_sntp.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"

#define CLOCK_READY_BIT BIT0
#define MINIMUM_TRUSTED_EPOCH 1704067200LL // 2024-01-01 00:00:00 UTC

static const char *TAG = "clock_sync";
static EventGroupHandle_t clock_events;
static portMUX_TYPE clock_lock = portMUX_INITIALIZER_UNLOCKED;
static bool rtc_update_pending;

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

static void clock_synchronized(struct timeval *time_value)
{
    (void)time_value;
    if (!clock_is_valid() || clock_events == NULL) return;
    portENTER_CRITICAL(&clock_lock);
    rtc_update_pending = true;
    portEXIT_CRITICAL(&clock_lock);
    xEventGroupSetBits(clock_events, CLOCK_READY_BIT);
    ESP_LOGI(TAG, "Clock synchronized over Wi-Fi");
}

static void persist_synchronized_clock(void)
{
    portENTER_CRITICAL(&clock_lock);
    bool should_update = rtc_update_pending;
    rtc_update_pending = false;
    portEXIT_CRITICAL(&clock_lock);
    if (!should_update) return;

    esp_err_t status = board_waveshare_5_rtc_write_epoch((int64_t)time(NULL));
    if (status == ESP_OK) {
        ESP_LOGI(TAG, "Battery-backed RTC updated from network UTC");
    } else {
        portENTER_CRITICAL(&clock_lock);
        rtc_update_pending = true;
        portEXIT_CRITICAL(&clock_lock);
        ESP_LOGW(TAG, "Network time is valid, but RTC update failed: %s", esp_err_to_name(status));
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
    esp_sntp_config_t config = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
    config.wait_for_sync = false;
    config.sync_cb = clock_synchronized;
    esp_err_t status = esp_netif_sntp_init(&config);
    if (status != ESP_OK) {
        vEventGroupDelete(clock_events);
        clock_events = NULL;
        ESP_LOGW(TAG, "Unable to initialize asynchronous SNTP: %s", esp_err_to_name(status));
        return false;
    }
    ESP_LOGI(TAG, "Asynchronous network clock refresh started");
    return true;
}

bool clock_sync_wait(uint32_t timeout_ms)
{
    if (clock_is_valid()) {
        persist_synchronized_clock();
        return true;
    }
    if (clock_events == NULL) return false;
    EventBits_t bits = xEventGroupWaitBits(
        clock_events,
        CLOCK_READY_BIT,
        pdFALSE,
        pdTRUE,
        pdMS_TO_TICKS(timeout_ms)
    );
    bool ready = (bits & CLOCK_READY_BIT) != 0 && clock_is_valid();
    if (ready) persist_synchronized_clock();
    return ready;
}
