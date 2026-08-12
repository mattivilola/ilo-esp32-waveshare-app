#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "dashboard_model.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*mac_transport_model_callback_t)(const dashboard_model_t *model);

bool mac_transport_start(mac_transport_model_callback_t callback);
bool mac_transport_start_wifi_only(void);
bool mac_transport_wait_for_network(uint32_t timeout_ms);
bool mac_transport_request_x_news_refresh(void);
bool mac_transport_request_codex_continue(const char *task_id);
bool mac_transport_update_wifi(const char *ssid, const char *password);
size_t mac_transport_scan_wifi(char (*ssids)[33], size_t maximum_count);

#ifdef __cplusplus
}
#endif
