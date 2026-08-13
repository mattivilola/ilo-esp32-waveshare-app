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

typedef enum {
    DASHBOARD_CODEX_CONTINUE_SENDING,
    DASHBOARD_CODEX_CONTINUE_ACCEPTED,
    DASHBOARD_CODEX_CONTINUE_UNAVAILABLE,
    DASHBOARD_CODEX_CONTINUE_BUSY,
    DASHBOARD_CODEX_CONTINUE_REJECTED,
    DASHBOARD_CODEX_CONTINUE_FAILED,
} dashboard_codex_continue_state_t;

typedef bool (*dashboard_codex_continue_callback_t)(const char *task_id);

#define DASHBOARD_CODEX_CHAT_MAX_MESSAGES 6
#define DASHBOARD_CODEX_CHAT_TEXT_MAX 360

typedef enum {
    DASHBOARD_CODEX_CHAT_READY,
    DASHBOARD_CODEX_CHAT_UNAVAILABLE,
    DASHBOARD_CODEX_CHAT_BUSY,
    DASHBOARD_CODEX_CHAT_FAILED,
} dashboard_codex_chat_state_t;

typedef enum {
    DASHBOARD_CODEX_CHAT_USER,
    DASHBOARD_CODEX_CHAT_ASSISTANT,
} dashboard_codex_chat_role_t;

typedef struct {
    dashboard_codex_chat_role_t role;
    char text[DASHBOARD_CODEX_CHAT_TEXT_MAX + 1];
} dashboard_codex_chat_message_t;

typedef struct {
    dashboard_codex_chat_state_t state;
    char task_id[81];
    char title[81];
    char status_message[96];
    uint8_t message_count;
    dashboard_codex_chat_message_t messages[DASHBOARD_CODEX_CHAT_MAX_MESSAGES];
} dashboard_codex_chat_detail_t;

typedef bool (*dashboard_codex_chat_callback_t)(const char *task_id);

esp_err_t dashboard_ui_init(esp_lcd_panel_handle_t lcd);
esp_err_t dashboard_ui_present_boot(void);
void dashboard_ui_set_model(const dashboard_model_t *model);
typedef bool (*dashboard_wifi_update_callback_t)(const char *ssid, const char *password);
typedef size_t (*dashboard_wifi_scan_callback_t)(char (*ssids)[33], size_t maximum_count);
void dashboard_ui_set_wifi_update_callback(dashboard_wifi_update_callback_t callback);
void dashboard_ui_set_wifi_scan_callback(dashboard_wifi_scan_callback_t callback);
void dashboard_ui_set_connection_state(dashboard_connection_state_t state);
void dashboard_ui_set_weather(const weather_model_t *model);
void dashboard_ui_set_x_news_refresh_callback(dashboard_x_news_refresh_callback_t callback);
void dashboard_ui_set_x_news_refresh_state(dashboard_x_news_refresh_state_t state);
void dashboard_ui_set_codex_continue_callback(dashboard_codex_continue_callback_t callback);
void dashboard_ui_set_codex_continue_state(dashboard_codex_continue_state_t state);
void dashboard_ui_set_codex_chat_callback(dashboard_codex_chat_callback_t callback);
void dashboard_ui_set_codex_chat_detail(const dashboard_codex_chat_detail_t *detail);
esp_err_t dashboard_ui_capture_rgb565(uint8_t **pixels, size_t *size);

#ifdef __cplusplus
}
#endif
