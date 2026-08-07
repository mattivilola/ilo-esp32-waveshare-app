#pragma once

#include "dashboard_model.h"
#include "esp_err.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_touch.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    DASHBOARD_CONNECTION_ONLINE,
    DASHBOARD_CONNECTION_CONNECTING,
    DASHBOARD_CONNECTION_OFFLINE,
    DASHBOARD_CONNECTION_NOT_CONFIGURED,
} dashboard_connection_state_t;

esp_err_t dashboard_ui_init(esp_lcd_panel_handle_t lcd, esp_lcd_touch_handle_t touch);
void dashboard_ui_set_model(const dashboard_model_t *model);
void dashboard_ui_set_connection_state(dashboard_connection_state_t state);

#ifdef __cplusplus
}
#endif

