#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "dashboard_model.h"
#include "esp_err.h"
#include "esp_lcd_panel_ops.h"
#include "weather_model.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    DASHBOARD_CONNECTION_ONLINE,
    DASHBOARD_CONNECTION_CONNECTING,
    DASHBOARD_CONNECTION_OFFLINE,
    DASHBOARD_CONNECTION_NOT_CONFIGURED,
} dashboard_connection_state_t;

typedef enum {
    DASHBOARD_X_NEWS_REFRESH_FETCHING,
    DASHBOARD_X_NEWS_REFRESH_UPDATED,
    DASHBOARD_X_NEWS_REFRESH_DISABLED,
    DASHBOARD_X_NEWS_REFRESH_COOLDOWN,
    DASHBOARD_X_NEWS_REFRESH_BUSY,
    DASHBOARD_X_NEWS_REFRESH_FAILED,
} dashboard_x_news_refresh_state_t;

typedef bool (*dashboard_x_news_refresh_callback_t)(void);

esp_err_t dashboard_ui_init(esp_lcd_panel_handle_t lcd);
void dashboard_ui_set_model(const dashboard_model_t *model);
void dashboard_ui_set_connection_state(dashboard_connection_state_t state);
void dashboard_ui_set_weather(const weather_model_t *model);
void dashboard_ui_set_x_news_refresh_callback(dashboard_x_news_refresh_callback_t callback);
void dashboard_ui_set_x_news_refresh_state(dashboard_x_news_refresh_state_t state);
esp_err_t dashboard_ui_capture_rgb565(uint8_t **pixels, size_t *size);

#ifdef __cplusplus
}
#endif
