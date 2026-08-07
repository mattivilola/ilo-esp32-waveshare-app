#pragma once

#include "esp_err.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_touch.h"

#ifdef __cplusplus
extern "C" {
#endif

#define ILO_BOARD_WIDTH 800
#define ILO_BOARD_HEIGHT 480

esp_err_t board_waveshare_5_init(void);
esp_lcd_panel_handle_t board_waveshare_5_lcd(void);
esp_lcd_touch_handle_t board_waveshare_5_touch(void);

#ifdef __cplusplus
}
#endif

