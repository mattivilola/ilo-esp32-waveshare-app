#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint16_t screensaver_minutes;
    uint16_t display_off_minutes;
    uint16_t focus_minutes;
    bool hide_task_summaries;
    bool use_24_hour_clock;
    bool use_fahrenheit;
    int32_t clock_utc_offset_seconds;
    char clock_timezone_abbreviation[8];
} device_settings_t;

device_settings_t device_settings_load(void);
void device_settings_save(const device_settings_t *settings);
uint16_t device_settings_next_screensaver(uint16_t current);
uint16_t device_settings_next_display_off(uint16_t current);
uint16_t device_settings_next_focus(uint16_t current);

#ifdef __cplusplus
}
#endif
