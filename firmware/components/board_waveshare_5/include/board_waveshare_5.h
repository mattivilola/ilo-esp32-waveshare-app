#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "esp_lcd_panel_ops.h"

#ifdef __cplusplus
extern "C" {
#endif

#define ILO_BOARD_WIDTH 1024
#define ILO_BOARD_HEIGHT 600
#define ILO_BOARD_MODEL "Waveshare ESP32-S3-Touch-LCD-5B"
#define ILO_BOARD_SKU "28151"

esp_err_t board_waveshare_5_init(void);
esp_lcd_panel_handle_t board_waveshare_5_lcd(void);
bool board_waveshare_5_read_touch(uint16_t *x, uint16_t *y);
esp_err_t board_waveshare_5_set_backlight(bool enabled);
bool board_waveshare_5_backlight_enabled(void);

#ifdef __cplusplus
}
#endif
