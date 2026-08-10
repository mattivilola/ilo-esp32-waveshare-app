#include "device_settings.h"

#include <stddef.h>

#include "esp_log.h"
#include "nvs.h"

#define SETTINGS_NAMESPACE "ilo_settings"
#define DEFAULT_SCREENSAVER_MINUTES 2
#define DEFAULT_DISPLAY_OFF_MINUTES 10
#define DEFAULT_FOCUS_MINUTES 25

static const char *TAG = "device_settings";

static bool allowed(uint16_t value, const uint16_t *choices, size_t count)
{
    for (size_t index = 0; index < count; ++index) {
        if (value == choices[index]) {
            return true;
        }
    }
    return false;
}

static uint16_t next_choice(uint16_t current, const uint16_t *choices, size_t count)
{
    for (size_t index = 0; index < count; ++index) {
        if (current == choices[index]) {
            return choices[(index + 1) % count];
        }
    }
    return choices[0];
}

device_settings_t device_settings_load(void)
{
    static const uint16_t screensaver_choices[] = { 0, 2, 5 };
    static const uint16_t display_off_choices[] = { 0, 5, 10, 30 };
    static const uint16_t focus_choices[] = { 25, 45, 60 };
    device_settings_t settings = {
        .screensaver_minutes = DEFAULT_SCREENSAVER_MINUTES,
        .display_off_minutes = DEFAULT_DISPLAY_OFF_MINUTES,
        .focus_minutes = DEFAULT_FOCUS_MINUTES,
        .hide_task_summaries = false,
        .use_24_hour_clock = true,
        .use_fahrenheit = false,
    };
    nvs_handle_t handle;
    esp_err_t status = nvs_open(SETTINGS_NAMESPACE, NVS_READONLY, &handle);
    if (status == ESP_ERR_NVS_NOT_FOUND) {
        return settings;
    }
    if (status != ESP_OK) {
        ESP_LOGW(TAG, "Unable to read settings: %s", esp_err_to_name(status));
        return settings;
    }

    uint16_t screensaver = settings.screensaver_minutes;
    uint16_t display_off = settings.display_off_minutes;
    uint16_t focus = settings.focus_minutes;
    uint8_t hide_summaries = 0;
    uint8_t clock_24h = 1;
    uint8_t fahrenheit = 0;
    if (nvs_get_u16(handle, "saver_min", &screensaver) == ESP_OK
        && allowed(screensaver, screensaver_choices, sizeof(screensaver_choices) / sizeof(screensaver_choices[0]))) {
        settings.screensaver_minutes = screensaver;
    }
    if (nvs_get_u16(handle, "off_min", &display_off) == ESP_OK
        && allowed(display_off, display_off_choices, sizeof(display_off_choices) / sizeof(display_off_choices[0]))) {
        settings.display_off_minutes = display_off;
    }
    if (nvs_get_u16(handle, "focus_min", &focus) == ESP_OK
        && allowed(focus, focus_choices, sizeof(focus_choices) / sizeof(focus_choices[0]))) {
        settings.focus_minutes = focus;
    }
    if (nvs_get_u8(handle, "hide_summary", &hide_summaries) == ESP_OK) {
        settings.hide_task_summaries = hide_summaries == 1;
    }
    if (nvs_get_u8(handle, "clock_24h", &clock_24h) == ESP_OK) {
        settings.use_24_hour_clock = clock_24h == 1;
    }
    if (nvs_get_u8(handle, "fahrenheit", &fahrenheit) == ESP_OK) {
        settings.use_fahrenheit = fahrenheit == 1;
    }
    nvs_close(handle);
    return settings;
}

void device_settings_save(const device_settings_t *settings)
{
    if (settings == NULL) {
        return;
    }
    nvs_handle_t handle;
    esp_err_t status = nvs_open(SETTINGS_NAMESPACE, NVS_READWRITE, &handle);
    if (status != ESP_OK) {
        ESP_LOGE(TAG, "Unable to open settings: %s", esp_err_to_name(status));
        return;
    }
    if (status == ESP_OK) status = nvs_set_u16(handle, "saver_min", settings->screensaver_minutes);
    if (status == ESP_OK) status = nvs_set_u16(handle, "off_min", settings->display_off_minutes);
    if (status == ESP_OK) status = nvs_set_u16(handle, "focus_min", settings->focus_minutes);
    if (status == ESP_OK) status = nvs_set_u8(handle, "hide_summary", settings->hide_task_summaries ? 1 : 0);
    if (status == ESP_OK) status = nvs_set_u8(handle, "clock_24h", settings->use_24_hour_clock ? 1 : 0);
    if (status == ESP_OK) status = nvs_set_u8(handle, "fahrenheit", settings->use_fahrenheit ? 1 : 0);
    if (status == ESP_OK) status = nvs_commit(handle);
    nvs_close(handle);
    if (status != ESP_OK) {
        ESP_LOGE(TAG, "Unable to save settings: %s", esp_err_to_name(status));
    }
}

uint16_t device_settings_next_screensaver(uint16_t current)
{
    static const uint16_t choices[] = { 0, 2, 5 };
    return next_choice(current, choices, sizeof(choices) / sizeof(choices[0]));
}

uint16_t device_settings_next_display_off(uint16_t current)
{
    static const uint16_t choices[] = { 0, 5, 10, 30 };
    return next_choice(current, choices, sizeof(choices) / sizeof(choices[0]));
}

uint16_t device_settings_next_focus(uint16_t current)
{
    static const uint16_t choices[] = { 25, 45, 60 };
    return next_choice(current, choices, sizeof(choices) / sizeof(choices[0]));
}
