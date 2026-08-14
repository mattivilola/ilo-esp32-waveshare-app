#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "dashboard_model.h"
#include "dashboard_ui.h"
#include "ota_updater.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*mac_transport_model_callback_t)(const dashboard_model_t *model);

bool mac_transport_start(mac_transport_model_callback_t callback);
bool mac_transport_start_wifi_only(void);
bool mac_transport_wait_for_network(uint32_t timeout_ms);
bool mac_transport_request_x_news_refresh(void);
bool mac_transport_request_codex_chat(const char *task_id);
bool mac_transport_request_codex_action(const char *task_id, dashboard_codex_action_t action);
bool mac_transport_update_wifi(const char *ssid, const char *password);
size_t mac_transport_scan_wifi(char (*ssids)[33], size_t maximum_count);
size_t mac_transport_known_wifi(char (*ssids)[33], size_t maximum_count);
bool mac_transport_forget_wifi(const char *ssid);
void mac_transport_publish_ota_status(const ota_updater_status_t *status);
bool mac_transport_publish_focus_completion(const dashboard_focus_completion_t *completion);

#ifdef __cplusplus
}
#endif
