#include "mac_transport.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>

#include "cJSON.h"
#include "esp_check.h"
#include "esp_app_desc.h"
#include "esp_event.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_random.h"
#include "esp_tls.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "mbedtls/base64.h"
#include "mbedtls/sha256.h"
#include "mdns.h"
#include "nvs.h"
#include "dashboard_ui.h"
#include "usb_secure_channel.h"

#define WIFI_READY_BIT BIT0
#define FRAME_MAX 65536
#define BOARD_ID_MAX 81
#define HOST_ADDRESS_MAX 254
#define WIFI_SSID_MAX 33
#define WIFI_PASSWORD_MAX 64
#define PSK_SIZE 32
#define DISCOVERY_TIMEOUT_MS 2000
#define DISCOVERY_MAX_RESULTS 8
#define BOARD_SERVICE_TYPE "_iloboard"
#define BOARD_SERVICE_PROTOCOL "_tcp"
#define BOARD_SERVICE_INSTANCE_PREFIX "ilo-board-host-"
#define SCREEN_CAPTURE_VERSION 1
#define SCREEN_CAPTURE_WIDTH 1024
#define SCREEN_CAPTURE_HEIGHT 600
#define SCREEN_CAPTURE_BYTES (SCREEN_CAPTURE_WIDTH * SCREEN_CAPTURE_HEIGHT * 2)
// Base64 plus the JSON envelope must fit CONFIG_MBEDTLS_SSL_OUT_CONTENT_LEN (4096 bytes).
#define SCREEN_CAPTURE_CHUNK_BYTES 2880
#define SCREEN_CAPTURE_REQUEST_ID_MAX 64
#define TLS_IO_PROGRESS_TIMEOUT_MS 2000
#define CODEX_TASK_ID_MAX 80

typedef struct {
    char wifi_ssid[WIFI_SSID_MAX];
    char wifi_password[WIFI_PASSWORD_MAX];
    char board_id[BOARD_ID_MAX];
    char host_address[HOST_ADDRESS_MAX];
    uint16_t host_port;
    uint8_t psk[PSK_SIZE];
} mac_transport_config_t;

typedef enum {
    MAC_CHANNEL_WIFI,
    MAC_CHANNEL_USB,
} mac_channel_kind_t;

typedef struct {
    void *context;
    bool (*send_json)(void *context, cJSON *json);
    cJSON *(*read_json)(void *context);
    int (*wait_data)(void *context, uint32_t timeout_ms);
    mac_channel_kind_t kind;
} mac_channel_t;

static const char *TAG = "mac_transport";
static EventGroupHandle_t wifi_events;
static mac_transport_model_callback_t model_callback;
static bool mdns_available;
static portMUX_TYPE refresh_lock = portMUX_INITIALIZER_UNLOCKED;
static bool transport_online;
static bool x_news_refresh_requested;
static bool codex_chat_supported;
static bool codex_chat_requested;
static bool codex_chat_in_flight;
static char codex_chat_task_id[CODEX_TASK_ID_MAX + 1];
static char codex_chat_request_id[25];
static bool codex_continue_requested;
static bool codex_continue_in_flight;
static char codex_continue_task_id[CODEX_TASK_ID_MAX + 1];
static char codex_continue_request_id[25];
static bool wifi_scan_in_progress;
static bool wifi_scan_requested_once;
static bool wifi_reconnect_suspended;
static bool wifi_update_in_progress;
static TickType_t wifi_scan_last_started;
static size_t wifi_scan_count;
static char wifi_scan_ssids[4][33];
static TaskHandle_t wifi_scan_task_handle;
static SemaphoreHandle_t wifi_control_mutex;
static ota_updater_status_t ota_status_pending;
static bool ota_status_dirty;
static mac_channel_kind_t active_channel_kind;
static uint32_t active_channel_generation;
static bool active_channel_present;

static bool json_number_equals(cJSON *item, int expected);
static void copy_json_string(cJSON *object, const char *name, char *destination, size_t size);
static void copy_json_board_text(cJSON *object, const char *name, char *destination, size_t size);
static void make_board_text_font_safe(char *text);

static bool json_array_contains_string(cJSON *array, const char *value)
{
    if (!cJSON_IsArray(array) || value == NULL) return false;
    cJSON *item = NULL;
    cJSON_ArrayForEach(item, array) {
        if (cJSON_IsString(item) && strcmp(item->valuestring, value) == 0) return true;
    }
    return false;
}

typedef struct {
    char address[HOST_ADDRESS_MAX];
    uint16_t port;
} mac_endpoint_t;

static void wifi_scan_task(void *argument)
{
    (void)argument;
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        if (wifi_control_mutex == NULL
            || xSemaphoreTake(wifi_control_mutex, portMAX_DELAY) != pdTRUE) {
            portENTER_CRITICAL(&refresh_lock);
            wifi_scan_in_progress = false;
            portEXIT_CRITICAL(&refresh_lock);
            continue;
        }

        portENTER_CRITICAL(&refresh_lock);
        wifi_reconnect_suspended = true;
        portEXIT_CRITICAL(&refresh_lock);

        wifi_scan_config_t scan = { .show_hidden = false };
        esp_err_t scan_status = esp_wifi_stop();
        if (scan_status == ESP_OK) scan_status = esp_wifi_start();
        if (scan_status == ESP_OK) vTaskDelay(pdMS_TO_TICKS(250));
        if (scan_status == ESP_OK) scan_status = esp_wifi_scan_start(&scan, true);

        uint16_t count = 20;
        wifi_ap_record_t *records = calloc(count, sizeof(*records));
        size_t accepted = 0;
        esp_err_t records_status = ESP_OK;
        if (scan_status == ESP_OK && records != NULL
            && (records_status = esp_wifi_scan_get_ap_records(&count, records)) == ESP_OK) {
            char discovered[4][33] = { 0 };
            for (uint16_t index = 0; index < count && accepted < 4; ++index) {
                wifi_auth_mode_t authmode = records[index].authmode;
                bool personal_network = authmode == WIFI_AUTH_WPA2_PSK
                    || authmode == WIFI_AUTH_WPA_WPA2_PSK
                    || authmode == WIFI_AUTH_WPA3_PSK
                    || authmode == WIFI_AUTH_WPA2_WPA3_PSK;
                if (records[index].ssid[0] == 0 || !personal_network) continue;
                bool duplicate = false;
                for (size_t existing = 0; existing < accepted; ++existing) {
                    if (strcmp(discovered[existing], (const char *)records[index].ssid) == 0) {
                        duplicate = true;
                        break;
                    }
                }
                if (!duplicate) {
                    strlcpy(discovered[accepted], (const char *)records[index].ssid, 33);
                    ++accepted;
                }
            }
            portENTER_CRITICAL(&refresh_lock);
            memcpy(wifi_scan_ssids, discovered, sizeof(discovered));
            wifi_scan_count = accepted;
            portEXIT_CRITICAL(&refresh_lock);
        } else if (scan_status == ESP_OK && records == NULL) {
            records_status = ESP_ERR_NO_MEM;
            (void)esp_wifi_clear_ap_list();
        }
        free(records);
        portENTER_CRITICAL(&refresh_lock);
        wifi_scan_in_progress = false;
        bool should_reconnect = !wifi_update_in_progress;
        if (should_reconnect) wifi_reconnect_suspended = false;
        portEXIT_CRITICAL(&refresh_lock);
        if (scan_status != ESP_OK) {
            ESP_LOGW(TAG, "Wi-Fi scan failed: %s", esp_err_to_name(scan_status));
        } else if (records_status != ESP_OK) {
            ESP_LOGW(TAG, "Wi-Fi scan results failed: %s", esp_err_to_name(records_status));
        } else {
            ESP_LOGI(TAG, "Wi-Fi scan examined %u APs; showing %u compatible networks",
                     (unsigned int)count, (unsigned int)accepted);
        }
        if (should_reconnect) (void)esp_wifi_connect();
        xSemaphoreGive(wifi_control_mutex);
    }
}

static void wifi_event(void *argument, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        portENTER_CRITICAL(&refresh_lock);
        bool connect = !wifi_reconnect_suspended;
        portEXIT_CRITICAL(&refresh_lock);
        if (connect) esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        xEventGroupClearBits(wifi_events, WIFI_READY_BIT);
        portENTER_CRITICAL(&refresh_lock);
        bool reconnect = !wifi_reconnect_suspended;
        portEXIT_CRITICAL(&refresh_lock);
        if (reconnect) {
            dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_OFFLINE);
            esp_wifi_connect();
        }
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        xEventGroupSetBits(wifi_events, WIFI_READY_BIT);
    }
}

static esp_err_t nvs_read_string(
    nvs_handle_t handle,
    const char *key,
    char *destination,
    size_t destination_size
)
{
    size_t required_size = destination_size;
    esp_err_t status = nvs_get_str(handle, key, destination, &required_size);
    if (status == ESP_OK && (required_size == 0 || required_size > destination_size)) {
        return ESP_ERR_INVALID_SIZE;
    }
    return status;
}

static esp_err_t load_config(mac_transport_config_t *config)
{
    nvs_handle_t handle;
    ESP_RETURN_ON_ERROR(nvs_open("ilo_board", NVS_READONLY, &handle), TAG, "Board is not provisioned");

    esp_err_t status = nvs_read_string(handle, "wifi_ssid", config->wifi_ssid, sizeof(config->wifi_ssid));
    if (status == ESP_OK) {
        status = nvs_read_string(handle, "wifi_password", config->wifi_password, sizeof(config->wifi_password));
    }
    if (status == ESP_OK) {
        status = nvs_read_string(handle, "board_id", config->board_id, sizeof(config->board_id));
    }
    if (status == ESP_OK) {
        status = nvs_read_string(handle, "host_address", config->host_address, sizeof(config->host_address));
    }
    if (status == ESP_OK) {
        status = nvs_get_u16(handle, "host_port", &config->host_port);
    }
    size_t psk_size = sizeof(config->psk);
    if (status == ESP_OK) {
        status = nvs_get_blob(handle, "psk", config->psk, &psk_size);
        if (status == ESP_OK && psk_size != sizeof(config->psk)) {
            status = ESP_ERR_INVALID_SIZE;
        }
    }
    nvs_close(handle);

    if (status != ESP_OK || config->wifi_ssid[0] == 0 || config->board_id[0] == 0
        || config->host_address[0] == 0 || config->host_port == 0) {
        return status == ESP_OK ? ESP_ERR_INVALID_STATE : status;
    }
    return ESP_OK;
}

static esp_err_t load_wifi_config(mac_transport_config_t *config)
{
    nvs_handle_t handle;
    ESP_RETURN_ON_ERROR(nvs_open("ilo_board", NVS_READONLY, &handle), TAG, "Wi-Fi is not configured");
    esp_err_t status = nvs_read_string(handle, "wifi_ssid", config->wifi_ssid, sizeof(config->wifi_ssid));
    if (status == ESP_OK) {
        status = nvs_read_string(handle, "wifi_password", config->wifi_password, sizeof(config->wifi_password));
    }
    nvs_close(handle);
    return status == ESP_OK && config->wifi_ssid[0] != 0 ? ESP_OK : ESP_ERR_INVALID_STATE;
}

static esp_err_t wifi_start(const mac_transport_config_t *transport_config)
{
    wifi_events = xEventGroupCreate();
    if (wifi_events == NULL) {
        return ESP_ERR_NO_MEM;
    }
    ESP_RETURN_ON_ERROR(esp_netif_init(), TAG, "netif init failed");
    ESP_RETURN_ON_ERROR(esp_event_loop_create_default(), TAG, "event loop failed");
    esp_netif_create_default_wifi_sta();
    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_RETURN_ON_ERROR(esp_wifi_init(&init), TAG, "Wi-Fi init failed");
    ESP_RETURN_ON_ERROR(
        esp_wifi_set_country_code("FI", true),
        TAG,
        "Wi-Fi country configuration failed"
    );
    wifi_control_mutex = xSemaphoreCreateMutex();
    if (wifi_control_mutex == NULL) return ESP_ERR_NO_MEM;
    if (xTaskCreate(wifi_scan_task, "wifi_scan", 4096, NULL, 3, &wifi_scan_task_handle) != pdPASS) {
        wifi_scan_task_handle = NULL;
        return ESP_ERR_NO_MEM;
    }
    ESP_RETURN_ON_ERROR(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, wifi_event, NULL), TAG, "Wi-Fi handler failed");
    ESP_RETURN_ON_ERROR(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, wifi_event, NULL), TAG, "IP handler failed");

    ESP_RETURN_ON_ERROR(esp_wifi_set_mode(WIFI_MODE_STA), TAG, "Wi-Fi mode failed");
    if (transport_config->wifi_ssid[0] != 0) {
        wifi_config_t config = { 0 };
        memcpy(config.sta.ssid, transport_config->wifi_ssid, strlen(transport_config->wifi_ssid));
        memcpy(config.sta.password, transport_config->wifi_password, strlen(transport_config->wifi_password));
        config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;
        ESP_RETURN_ON_ERROR(esp_wifi_set_config(WIFI_IF_STA, &config), TAG, "Wi-Fi config failed");
    }
    return esp_wifi_start();
}

static bool txt_value_matches(const mdns_result_t *result, const char *key, const char *value)
{
    if (result == NULL || key == NULL || value == NULL) {
        return false;
    }
    size_t value_size = strlen(value);
    for (size_t index = 0; index < result->txt_count; ++index) {
        const mdns_txt_item_t *item = &result->txt[index];
        size_t item_value_size = result->txt_value_len != NULL
            ? result->txt_value_len[index]
            : (item->value != NULL ? strlen(item->value) : 0);
        if (item->key != NULL && strcmp(item->key, key) == 0
            && item->value != NULL && item_value_size == value_size
            && memcmp(item->value, value, value_size) == 0) {
            return true;
        }
    }
    return false;
}

static bool instance_matches_board(const mdns_result_t *result, const char *board_id)
{
    if (result == NULL || result->instance_name == NULL || board_id == NULL) {
        return false;
    }
    size_t board_id_size = strlen(board_id);
    const char *suffix = board_id + (board_id_size > 8 ? board_id_size - 8 : 0);
    char expected[sizeof(BOARD_SERVICE_INSTANCE_PREFIX) + 8] = { 0 };
    int written = snprintf(expected, sizeof(expected), "%s%s", BOARD_SERVICE_INSTANCE_PREFIX, suffix);
    return written > 0 && (size_t)written < sizeof(expected)
        && strcmp(result->instance_name, expected) == 0;
}

static bool result_ipv4_address(const mdns_result_t *result, char *destination, size_t destination_size)
{
    if (result == NULL || destination == NULL || destination_size == 0) {
        return false;
    }
    for (const mdns_ip_addr_t *address = result->addr; address != NULL; address = address->next) {
        if (address->addr.type != ESP_IPADDR_TYPE_V4) {
            continue;
        }
        int written = snprintf(
            destination,
            destination_size,
            IPSTR,
            IP2STR(&address->addr.u_addr.ip4)
        );
        return written > 0 && (size_t)written < destination_size;
    }
    return false;
}

static bool discover_endpoint(const mac_transport_config_t *config, mac_endpoint_t *endpoint)
{
    if (!mdns_available || config == NULL || endpoint == NULL) {
        return false;
    }

    mdns_result_t *results = NULL;
    esp_err_t status = mdns_query_ptr(
        BOARD_SERVICE_TYPE,
        BOARD_SERVICE_PROTOCOL,
        DISCOVERY_TIMEOUT_MS,
        DISCOVERY_MAX_RESULTS,
        &results
    );
    if (status != ESP_OK) {
        ESP_LOGW(TAG, "Bonjour lookup failed: %s; using provisioned host fallback", esp_err_to_name(status));
        return false;
    }

    bool found = false;
    for (const mdns_result_t *result = results; result != NULL; result = result->next) {
        if (!instance_matches_board(result, config->board_id)
            || result->port == 0
            || !txt_value_matches(result, "v", "1")
            || !txt_value_matches(result, "transport", "tls-psk-tcp")) {
            continue;
        }
        if (result_ipv4_address(result, endpoint->address, sizeof(endpoint->address))) {
            endpoint->port = result->port;
            found = true;
            break;
        }
    }
    mdns_query_results_free(results);

    if (found) {
        ESP_LOGI(TAG, "Using compatible Bonjour host for the paired board");
    } else {
        ESP_LOGI(TAG, "No compatible Bonjour host found; using provisioned host fallback");
    }
    return found;
}

static mac_endpoint_t endpoint_for_connection(const mac_transport_config_t *config)
{
    mac_endpoint_t endpoint = { .port = config->host_port };
    strlcpy(endpoint.address, config->host_address, sizeof(endpoint.address));
    discover_endpoint(config, &endpoint);
    return endpoint;
}

static bool save_host_endpoint(mac_transport_config_t *config, const char *address, uint16_t port)
{
    if (config == NULL || address == NULL || address[0] == 0 || port == 0
        || strlen(address) >= sizeof(config->host_address)) return false;
    nvs_handle_t handle = 0;
    esp_err_t status = nvs_open("ilo_board", NVS_READWRITE, &handle);
    if (status == ESP_OK) status = nvs_set_str(handle, "host_address", address);
    if (status == ESP_OK) status = nvs_set_u16(handle, "host_port", port);
    if (status == ESP_OK) status = nvs_commit(handle);
    if (handle != 0) nvs_close(handle);
    if (status != ESP_OK) {
        ESP_LOGW(TAG, "Could not save Mac endpoint learned over USB: %s", esp_err_to_name(status));
        return false;
    }
    strlcpy(config->host_address, address, sizeof(config->host_address));
    config->host_port = port;
    ESP_LOGI(TAG, "Updated provisioned Mac endpoint from authenticated USB session");
    return true;
}

static bool tls_write_all(esp_tls_t *tls, const uint8_t *data, size_t size)
{
    size_t sent = 0;
    TickType_t last_progress = xTaskGetTickCount();
    while (sent < size) {
        ssize_t result = esp_tls_conn_write(tls, data + sent, size - sent);
        if (result == ESP_TLS_ERR_SSL_WANT_READ || result == ESP_TLS_ERR_SSL_WANT_WRITE) {
            if ((xTaskGetTickCount() - last_progress) >= pdMS_TO_TICKS(TLS_IO_PROGRESS_TIMEOUT_MS)) {
                ESP_LOGW(TAG, "TLS write made no progress for %u ms", TLS_IO_PROGRESS_TIMEOUT_MS);
                return false;
            }
            vTaskDelay(pdMS_TO_TICKS(1));
            continue;
        }
        if (result <= 0) {
            ESP_LOGW(TAG, "TLS write failed after %u/%u bytes: %d", (unsigned)sent, (unsigned)size, (int)result);
            return false;
        }
        sent += (size_t)result;
        last_progress = xTaskGetTickCount();
    }
    return true;
}

static bool tls_read_all(esp_tls_t *tls, uint8_t *data, size_t size)
{
    size_t received = 0;
    TickType_t last_progress = xTaskGetTickCount();
    while (received < size) {
        ssize_t result = esp_tls_conn_read(tls, data + received, size - received);
        if (result == ESP_TLS_ERR_SSL_WANT_READ || result == ESP_TLS_ERR_SSL_WANT_WRITE) {
            if ((xTaskGetTickCount() - last_progress) >= pdMS_TO_TICKS(TLS_IO_PROGRESS_TIMEOUT_MS)) {
                ESP_LOGI(TAG, "TLS peer stopped responding; reconnecting");
                return false;
            }
            vTaskDelay(pdMS_TO_TICKS(1));
            continue;
        }
        if (result <= 0) {
            return false;
        }
        received += (size_t)result;
        last_progress = xTaskGetTickCount();
    }
    return true;
}

static bool send_json(esp_tls_t *tls, cJSON *json)
{
    char *payload = cJSON_PrintUnformatted(json);
    if (payload == NULL) {
        return false;
    }
    size_t size = strlen(payload);
    uint8_t header[4] = {
        (uint8_t)((size >> 24) & 0xff),
        (uint8_t)((size >> 16) & 0xff),
        (uint8_t)((size >> 8) & 0xff),
        (uint8_t)(size & 0xff),
    };
    bool ok = size > 0 && size <= FRAME_MAX
        && tls_write_all(tls, header, sizeof(header))
        && tls_write_all(tls, (const uint8_t *)payload, size);
    free(payload);
    return ok;
}

static bool tls_channel_send_json(void *context, cJSON *json)
{
    return send_json((esp_tls_t *)context, json);
}

static cJSON *read_json(esp_tls_t *tls);

static cJSON *tls_channel_read_json(void *context)
{
    return read_json((esp_tls_t *)context);
}

static int wait_for_tls_data(esp_tls_t *tls, uint32_t timeout_ms);

static int tls_channel_wait_data(void *context, uint32_t timeout_ms)
{
    return wait_for_tls_data((esp_tls_t *)context, timeout_ms);
}

static bool usb_channel_send_json(void *context, cJSON *json)
{
    return usb_secure_channel_send_json((usb_secure_channel_t *)context, json);
}

static cJSON *usb_channel_read_json(void *context)
{
    usb_secure_channel_t *channel = context;
    if (!channel->pending_data && usb_secure_channel_wait_data(channel, 10000) != 1) return NULL;
    return usb_secure_channel_read_json(channel);
}

static int usb_channel_wait_data(void *context, uint32_t timeout_ms)
{
    return usb_secure_channel_wait_data((usb_secure_channel_t *)context, timeout_ms);
}

static bool channel_send_json(mac_channel_t *channel, cJSON *json)
{
    return channel->send_json(channel->context, json);
}

static cJSON *channel_read_json(mac_channel_t *channel)
{
    return channel->read_json(channel->context);
}

static int channel_wait_data(mac_channel_t *channel, uint32_t timeout_ms)
{
    return channel->wait_data(channel->context, timeout_ms);
}

static const char *ota_state_name(ota_updater_state_t state)
{
    switch (state) {
    case OTA_UPDATER_DISABLED: return "disabled";
    case OTA_UPDATER_IDLE: return "idle";
    case OTA_UPDATER_CHECKING: return "checking";
    case OTA_UPDATER_UP_TO_DATE: return "upToDate";
    case OTA_UPDATER_AVAILABLE: return "available";
    case OTA_UPDATER_DOWNLOADING: return "downloading";
    case OTA_UPDATER_VERIFYING: return "verifying";
    case OTA_UPDATER_REBOOTING: return "rebooting";
    case OTA_UPDATER_FAILED: return "failed";
    default: return "failed";
    }
}

static bool send_pending_ota_status(mac_channel_t *channel)
{
    portENTER_CRITICAL(&refresh_lock);
    bool dirty = ota_status_dirty;
    ota_updater_status_t status = ota_status_pending;
    ota_status_dirty = false;
    portEXIT_CRITICAL(&refresh_lock);
    if (!dirty) return true;
    cJSON *message = cJSON_CreateObject();
    if (message == NULL) return false;
    cJSON_AddStringToObject(message, "type", "firmwareUpdateStatus");
    cJSON_AddNumberToObject(message, "version", 1);
    cJSON_AddStringToObject(message, "state", ota_state_name(status.state));
    cJSON_AddStringToObject(message, "currentVersion", status.current_version);
    if (status.available_version[0] != 0) cJSON_AddStringToObject(message, "availableVersion", status.available_version);
    cJSON_AddNumberToObject(message, "progressPercent", status.progress_percent);
    cJSON_AddStringToObject(message, "message", status.detail);
    bool sent = channel_send_json(channel, message);
    cJSON_Delete(message);
    return sent;
}

static bool handle_firmware_update_command(cJSON *message)
{
    cJSON *version = cJSON_GetObjectItemCaseSensitive(message, "version");
    cJSON *action = cJSON_GetObjectItemCaseSensitive(message, "action");
    if (!json_number_equals(version, 1) || !cJSON_IsString(action)) return false;
    if (strcmp(action->valuestring, "check") == 0) return ota_updater_request_check();
    if (strcmp(action->valuestring, "install") == 0) return ota_updater_request_install();
    return false;
}

static bool take_x_news_refresh_request(void)
{
    portENTER_CRITICAL(&refresh_lock);
    bool requested = x_news_refresh_requested;
    x_news_refresh_requested = false;
    portEXIT_CRITICAL(&refresh_lock);
    return requested;
}

static bool take_codex_continue_request(char *task_id, size_t task_id_size, char *request_id, size_t request_id_size)
{
    portENTER_CRITICAL(&refresh_lock);
    bool requested = codex_continue_requested;
    if (requested) {
        strlcpy(task_id, codex_continue_task_id, task_id_size);
        strlcpy(request_id, codex_continue_request_id, request_id_size);
        codex_continue_requested = false;
        codex_continue_in_flight = true;
    }
    portEXIT_CRITICAL(&refresh_lock);
    return requested;
}

static bool take_codex_chat_request(char *task_id, size_t task_id_size, char *request_id, size_t request_id_size)
{
    portENTER_CRITICAL(&refresh_lock);
    bool requested = codex_chat_requested;
    if (requested) {
        strlcpy(task_id, codex_chat_task_id, task_id_size);
        strlcpy(request_id, codex_chat_request_id, request_id_size);
        codex_chat_requested = false;
        codex_chat_in_flight = true;
    }
    portEXIT_CRITICAL(&refresh_lock);
    return requested;
}

static bool send_codex_chat_request(mac_channel_t *channel, const char *task_id, const char *request_id)
{
    cJSON *request = cJSON_CreateObject();
    if (request == NULL) return false;
    cJSON_AddStringToObject(request, "type", "codexChatRequest");
    cJSON_AddNumberToObject(request, "version", 1);
    cJSON_AddStringToObject(request, "requestID", request_id);
    cJSON_AddStringToObject(request, "taskID", task_id);
    bool ok = channel_send_json(channel, request);
    cJSON_Delete(request);
    ESP_LOGI(TAG, "Codex chat detail request %s", ok ? "sent" : "failed");
    return ok;
}

static void handle_codex_chat_detail(cJSON *message)
{
    cJSON *version = cJSON_GetObjectItemCaseSensitive(message, "version");
    cJSON *request_id = cJSON_GetObjectItemCaseSensitive(message, "requestID");
    cJSON *task_id = cJSON_GetObjectItemCaseSensitive(message, "taskID");
    cJSON *status = cJSON_GetObjectItemCaseSensitive(message, "status");
    if (!json_number_equals(version, 1) || !cJSON_IsString(request_id)
        || !cJSON_IsString(task_id) || !cJSON_IsString(status)) return;

    bool matches = false;
    portENTER_CRITICAL(&refresh_lock);
    matches = codex_chat_in_flight
        && strcmp(request_id->valuestring, codex_chat_request_id) == 0
        && strcmp(task_id->valuestring, codex_chat_task_id) == 0;
    if (matches) codex_chat_in_flight = false;
    portEXIT_CRITICAL(&refresh_lock);
    if (!matches) {
        ESP_LOGW(TAG, "Ignoring unmatched Codex chat detail response");
        return;
    }

    dashboard_codex_chat_detail_t *detail = calloc(1, sizeof(*detail));
    if (detail == NULL) {
        dashboard_ui_set_codex_chat_detail(NULL);
        return;
    }
    detail->state = DASHBOARD_CODEX_CHAT_FAILED;
    if (strcmp(status->valuestring, "ready") == 0) {
        detail->state = DASHBOARD_CODEX_CHAT_READY;
    } else if (strcmp(status->valuestring, "unavailable") == 0) {
        detail->state = DASHBOARD_CODEX_CHAT_UNAVAILABLE;
    } else if (strcmp(status->valuestring, "busy") == 0) {
        detail->state = DASHBOARD_CODEX_CHAT_BUSY;
    }
    copy_json_string(message, "taskID", detail->task_id, sizeof(detail->task_id));
    copy_json_board_text(message, "title", detail->title, sizeof(detail->title));
    copy_json_board_text(message, "message", detail->status_message, sizeof(detail->status_message));

    cJSON *messages = cJSON_GetObjectItemCaseSensitive(message, "messages");
    if (detail->state == DASHBOARD_CODEX_CHAT_READY && cJSON_IsArray(messages)) {
        cJSON *item = NULL;
        cJSON_ArrayForEach(item, messages) {
            if (detail->message_count >= DASHBOARD_CODEX_CHAT_MAX_MESSAGES || !cJSON_IsObject(item)) break;
            cJSON *role = cJSON_GetObjectItemCaseSensitive(item, "role");
            cJSON *text = cJSON_GetObjectItemCaseSensitive(item, "text");
            if (!cJSON_IsString(role) || !cJSON_IsString(text) || text->valuestring[0] == 0) continue;
            dashboard_codex_chat_message_t *target = &detail->messages[detail->message_count];
            if (strcmp(role->valuestring, "user") == 0) {
                target->role = DASHBOARD_CODEX_CHAT_USER;
            } else if (strcmp(role->valuestring, "assistant") == 0) {
                target->role = DASHBOARD_CODEX_CHAT_ASSISTANT;
            } else {
                continue;
            }
            strlcpy(target->text, text->valuestring, sizeof(target->text));
            make_board_text_font_safe(target->text);
            ++detail->message_count;
        }
    }
    dashboard_ui_set_codex_chat_detail(detail);
    free(detail);
}

static bool send_codex_continue_request(mac_channel_t *channel, const char *task_id, const char *request_id)
{
    cJSON *request = cJSON_CreateObject();
    if (request == NULL) return false;
    cJSON_AddStringToObject(request, "type", "codexContinueRequest");
    cJSON_AddNumberToObject(request, "version", 1);
    cJSON_AddStringToObject(request, "requestID", request_id);
    cJSON_AddStringToObject(request, "taskID", task_id);
    cJSON_AddStringToObject(request, "action", "continue");
    bool ok = channel_send_json(channel, request);
    cJSON_Delete(request);
    if (ok) {
        ESP_LOGI(TAG, "Fixed Codex continue request sent to paired Mac");
    }
    return ok;
}

static void handle_codex_continue_status(cJSON *message)
{
    cJSON *version = cJSON_GetObjectItemCaseSensitive(message, "version");
    cJSON *request_id = cJSON_GetObjectItemCaseSensitive(message, "requestID");
    cJSON *status = cJSON_GetObjectItemCaseSensitive(message, "status");
    if (!json_number_equals(version, 1) || !cJSON_IsString(request_id) || !cJSON_IsString(status)) return;

    bool matches = false;
    portENTER_CRITICAL(&refresh_lock);
    matches = codex_continue_in_flight
        && strcmp(request_id->valuestring, codex_continue_request_id) == 0;
    if (matches) codex_continue_in_flight = false;
    portEXIT_CRITICAL(&refresh_lock);
    if (!matches) {
        ESP_LOGW(TAG, "Ignoring unmatched Codex continue response");
        return;
    }

    dashboard_codex_continue_state_t state = DASHBOARD_CODEX_CONTINUE_FAILED;
    if (strcmp(status->valuestring, "accepted") == 0) {
        state = DASHBOARD_CODEX_CONTINUE_ACCEPTED;
    } else if (strcmp(status->valuestring, "unavailable") == 0) {
        state = DASHBOARD_CODEX_CONTINUE_UNAVAILABLE;
    } else if (strcmp(status->valuestring, "busy") == 0) {
        state = DASHBOARD_CODEX_CONTINUE_BUSY;
    } else if (strcmp(status->valuestring, "rejected") == 0) {
        state = DASHBOARD_CODEX_CONTINUE_REJECTED;
    }
    ESP_LOGI(TAG, "Codex continue status: %s", status->valuestring);
    dashboard_ui_set_codex_continue_state(state);
}

static bool send_x_news_refresh_request(mac_channel_t *channel)
{
    char request_id[25];
    snprintf(
        request_id,
        sizeof(request_id),
        "board-%08lx-%08lx",
        (unsigned long)esp_random(),
        (unsigned long)esp_random()
    );
    cJSON *request = cJSON_CreateObject();
    if (request == NULL) return false;
    cJSON_AddStringToObject(request, "type", "xNewsRefreshRequest");
    cJSON_AddStringToObject(request, "requestID", request_id);
    bool ok = channel_send_json(channel, request);
    cJSON_Delete(request);
    if (ok) {
        ESP_LOGI(TAG, "X News refresh request sent to paired Mac");
    } else {
        ESP_LOGW(TAG, "X News refresh request could not be sent");
    }
    return ok;
}

static void handle_x_news_refresh_status(cJSON *message)
{
    cJSON *status = cJSON_GetObjectItemCaseSensitive(message, "status");
    if (!cJSON_IsString(status)) return;
    dashboard_x_news_refresh_state_t state = DASHBOARD_X_NEWS_REFRESH_FAILED;
    if (strcmp(status->valuestring, "fetching") == 0) {
        state = DASHBOARD_X_NEWS_REFRESH_FETCHING;
    } else if (strcmp(status->valuestring, "updated") == 0) {
        state = DASHBOARD_X_NEWS_REFRESH_UPDATED;
    } else if (strcmp(status->valuestring, "disabled") == 0) {
        state = DASHBOARD_X_NEWS_REFRESH_DISABLED;
    } else if (strcmp(status->valuestring, "cooldown") == 0) {
        state = DASHBOARD_X_NEWS_REFRESH_COOLDOWN;
    } else if (strcmp(status->valuestring, "busy") == 0) {
        state = DASHBOARD_X_NEWS_REFRESH_BUSY;
    }
    ESP_LOGI(TAG, "X News refresh status: %s", status->valuestring);
    dashboard_ui_set_x_news_refresh_state(state);
}

static bool valid_request_id(const char *value)
{
    if (value == NULL) {
        return false;
    }
    size_t size = strlen(value);
    if (size == 0 || size > SCREEN_CAPTURE_REQUEST_ID_MAX) {
        return false;
    }
    for (size_t index = 0; index < size; ++index) {
        char character = value[index];
        if (!((character >= 'a' && character <= 'z')
            || (character >= 'A' && character <= 'Z')
            || (character >= '0' && character <= '9')
            || character == '-')) {
            return false;
        }
    }
    return true;
}

static bool json_number_equals(cJSON *item, int expected)
{
    return cJSON_IsNumber(item) && item->valuedouble == (double)expected;
}

static bool send_capture_result(
    mac_channel_t *channel,
    const char *request_id,
    const char *status,
    const char *error_code,
    const char *message,
    size_t total_bytes,
    const char *sha256
)
{
    cJSON *result = cJSON_CreateObject();
    if (result == NULL) {
        return false;
    }
    cJSON_AddStringToObject(result, "type", "screenCaptureResult");
    cJSON_AddNumberToObject(result, "version", SCREEN_CAPTURE_VERSION);
    cJSON_AddStringToObject(result, "requestID", request_id);
    cJSON_AddStringToObject(result, "status", status);
    if (strcmp(status, "ok") == 0) {
        cJSON_AddNumberToObject(result, "totalBytes", total_bytes);
        cJSON_AddStringToObject(result, "sha256", sha256);
    } else {
        cJSON_AddStringToObject(result, "errorCode", error_code);
        cJSON_AddStringToObject(result, "message", message);
    }
    bool sent = channel_send_json(channel, result);
    cJSON_Delete(result);
    return sent;
}

static bool send_capture_begin(mac_channel_t *channel, const char *request_id, size_t total_bytes)
{
    cJSON *begin = cJSON_CreateObject();
    if (begin == NULL) {
        return false;
    }
    cJSON_AddStringToObject(begin, "type", "screenCaptureBegin");
    cJSON_AddNumberToObject(begin, "version", SCREEN_CAPTURE_VERSION);
    cJSON_AddStringToObject(begin, "requestID", request_id);
    cJSON_AddStringToObject(begin, "format", "rgb565le");
    cJSON_AddNumberToObject(begin, "width", SCREEN_CAPTURE_WIDTH);
    cJSON_AddNumberToObject(begin, "height", SCREEN_CAPTURE_HEIGHT);
    cJSON_AddNumberToObject(begin, "totalBytes", total_bytes);
    cJSON_AddNumberToObject(begin, "chunkBytes", SCREEN_CAPTURE_CHUNK_BYTES);
    cJSON_AddNumberToObject(
        begin,
        "chunkCount",
        (total_bytes + SCREEN_CAPTURE_CHUNK_BYTES - 1) / SCREEN_CAPTURE_CHUNK_BYTES
    );
    bool sent = channel_send_json(channel, begin);
    cJSON_Delete(begin);
    return sent;
}

static bool send_capture_chunk(
    mac_channel_t *channel,
    const char *request_id,
    size_t sequence,
    size_t offset,
    const uint8_t *pixels,
    size_t size
)
{
    size_t encoded_capacity = ((size + 2) / 3) * 4 + 1;
    char *encoded = malloc(encoded_capacity);
    if (encoded == NULL) {
        return false;
    }
    size_t encoded_size = 0;
    int status = mbedtls_base64_encode(
        (unsigned char *)encoded,
        encoded_capacity,
        &encoded_size,
        pixels,
        size
    );
    if (status != 0 || encoded_size >= encoded_capacity) {
        free(encoded);
        return false;
    }
    encoded[encoded_size] = 0;

    cJSON *chunk = cJSON_CreateObject();
    if (chunk == NULL) {
        free(encoded);
        return false;
    }
    cJSON_AddStringToObject(chunk, "type", "screenCaptureChunk");
    cJSON_AddNumberToObject(chunk, "version", SCREEN_CAPTURE_VERSION);
    cJSON_AddStringToObject(chunk, "requestID", request_id);
    cJSON_AddNumberToObject(chunk, "sequence", sequence);
    cJSON_AddNumberToObject(chunk, "offset", offset);
    cJSON_AddStringToObject(chunk, "data", encoded);
    bool sent = channel_send_json(channel, chunk);
    cJSON_Delete(chunk);
    free(encoded);
    return sent;
}

static bool handle_capture_request(mac_channel_t *channel, cJSON *message)
{
    cJSON *version = cJSON_GetObjectItemCaseSensitive(message, "version");
    cJSON *request_id = cJSON_GetObjectItemCaseSensitive(message, "requestID");
    cJSON *format = cJSON_GetObjectItemCaseSensitive(message, "format");
    cJSON *width = cJSON_GetObjectItemCaseSensitive(message, "width");
    cJSON *height = cJSON_GetObjectItemCaseSensitive(message, "height");
    const char *request_id_value = cJSON_IsString(request_id) ? request_id->valuestring : NULL;
    if (!valid_request_id(request_id_value)) {
        ESP_LOGW(TAG, "Capture request has an invalid request ID");
        return false;
    }
    ESP_LOGI(TAG, "Capture request %s received", request_id_value);
    if (!json_number_equals(version, SCREEN_CAPTURE_VERSION)
        || !cJSON_IsString(format) || strcmp(format->valuestring, "rgb565le") != 0
        || !json_number_equals(width, SCREEN_CAPTURE_WIDTH)
        || !json_number_equals(height, SCREEN_CAPTURE_HEIGHT)) {
        return send_capture_result(
            channel,
            request_id_value,
            "error",
            "unsupportedCapture",
            "Capture requires version 1 RGB565-LE at 1024x600.",
            0,
            NULL
        );
    }

    uint8_t *pixels = NULL;
    size_t total_bytes = 0;
    esp_err_t capture_status = dashboard_ui_capture_rgb565(&pixels, &total_bytes);
    if (capture_status != ESP_OK || pixels == NULL || total_bytes != SCREEN_CAPTURE_BYTES) {
        ESP_LOGW(TAG, "Framebuffer capture unavailable: %s (%u bytes)", esp_err_to_name(capture_status), (unsigned)total_bytes);
        if (pixels != NULL) {
            free(pixels);
        }
        return send_capture_result(
            channel,
            request_id_value,
            "error",
            "captureUnavailable",
            "The display framebuffer is not safely available.",
            0,
            NULL
        );
    }

    uint8_t digest[32] = {0};
    bool ok = mbedtls_sha256(pixels, total_bytes, digest, 0) == 0
        && send_capture_begin(channel, request_id_value, total_bytes);
    const size_t chunk_count = (total_bytes + SCREEN_CAPTURE_CHUNK_BYTES - 1) / SCREEN_CAPTURE_CHUNK_BYTES;
    ESP_LOGI(TAG, "Sending %u capture bytes in %u chunks", (unsigned)total_bytes, (unsigned)chunk_count);
    size_t sequence = 0;
    for (size_t offset = 0; ok && offset < total_bytes; ++sequence) {
        size_t chunk_size = total_bytes - offset;
        if (chunk_size > SCREEN_CAPTURE_CHUNK_BYTES) {
            chunk_size = SCREEN_CAPTURE_CHUNK_BYTES;
        }
        ok = send_capture_chunk(channel, request_id_value, sequence, offset, pixels + offset, chunk_size);
        offset += chunk_size;
    }

    char digest_hex[65];
    for (size_t index = 0; index < sizeof(digest); ++index) {
        snprintf(&digest_hex[index * 2], 3, "%02x", digest[index]);
    }
    digest_hex[64] = 0;
    if (ok) {
        ok = send_capture_result(channel, request_id_value, "ok", NULL, NULL, total_bytes, digest_hex);
    }
    if (ok) {
        ESP_LOGI(TAG, "Capture request %s completed", request_id_value);
    } else {
        ESP_LOGW(TAG, "Capture request %s failed at chunk %u/%u", request_id_value, (unsigned)sequence, (unsigned)chunk_count);
    }
    free(pixels);
    return ok;
}

static cJSON *read_json(esp_tls_t *tls)
{
    uint8_t header[4];
    if (!tls_read_all(tls, header, sizeof(header))) {
        return NULL;
    }
    size_t size = ((size_t)header[0] << 24) | ((size_t)header[1] << 16) | ((size_t)header[2] << 8) | header[3];
    if (size == 0 || size > FRAME_MAX) {
        return NULL;
    }
    char *payload = malloc(size + 1);
    if (payload == NULL) {
        return NULL;
    }
    if (!tls_read_all(tls, (uint8_t *)payload, size)) {
        free(payload);
        return NULL;
    }
    payload[size] = 0;
    cJSON *json = cJSON_Parse(payload);
    free(payload);
    return json;
}

static int wait_for_tls_data(esp_tls_t *tls, uint32_t timeout_ms)
{
    if (esp_tls_get_bytes_avail(tls) > 0) return 1;
    int socket_fd = -1;
    if (esp_tls_get_conn_sockfd(tls, &socket_fd) != ESP_OK || socket_fd < 0) return -1;
    fd_set read_fds;
    FD_ZERO(&read_fds);
    FD_SET(socket_fd, &read_fds);
    struct timeval timeout = {
        .tv_sec = timeout_ms / 1000,
        .tv_usec = (timeout_ms % 1000) * 1000,
    };
    return select(socket_fd + 1, &read_fds, NULL, NULL, &timeout);
}

static dashboard_task_state_t task_state(const char *value)
{
    if (value != NULL && strcmp(value, "active") == 0) return DASHBOARD_TASK_ACTIVE;
    if (value != NULL && strcmp(value, "waiting") == 0) return DASHBOARD_TASK_WAITING;
    if (value != NULL && strcmp(value, "completed") == 0) return DASHBOARD_TASK_COMPLETED;
    if (value != NULL && strcmp(value, "failed") == 0) return DASHBOARD_TASK_FAILED;
    return DASHBOARD_TASK_IDLE;
}

static dashboard_attention_t attention(const char *value)
{
    if (value != NULL && strcmp(value, "question") == 0) return DASHBOARD_ATTENTION_QUESTION;
    if (value != NULL && strcmp(value, "approval") == 0) return DASHBOARD_ATTENTION_APPROVAL;
    return DASHBOARD_ATTENTION_NONE;
}

static bool mac_power_state(const char *value, dashboard_mac_power_state_t *state)
{
    if (value == NULL || state == NULL) return false;
    if (strcmp(value, "battery") == 0) {
        *state = DASHBOARD_MAC_POWER_BATTERY;
    } else if (strcmp(value, "charging") == 0) {
        *state = DASHBOARD_MAC_POWER_CHARGING;
    } else if (strcmp(value, "powerAdapter") == 0) {
        *state = DASHBOARD_MAC_POWER_ADAPTER;
    } else if (strcmp(value, "full") == 0) {
        *state = DASHBOARD_MAC_POWER_FULL;
    } else {
        return false;
    }
    return true;
}

static void copy_json_string(cJSON *object, const char *name, char *destination, size_t size)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(object, name);
    strlcpy(destination, cJSON_IsString(item) ? item->valuestring : "", size);
}

static void copy_json_software_version(cJSON *object, const char *name, char *destination, size_t size)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(object, name);
    const char *value = cJSON_IsString(item) ? item->valuestring : NULL;
    size_t length = value != NULL ? strlen(value) : 0;
    if (length == 0 || length > DASHBOARD_VERSION_MAX) {
        destination[0] = 0;
        return;
    }
    for (size_t index = 0; index < length; ++index) {
        char character = value[index];
        if (!((character >= 'a' && character <= 'z')
            || (character >= 'A' && character <= 'Z')
            || (character >= '0' && character <= '9')
            || character == '.' || character == '(' || character == ')'
            || character == '+' || character == '-' || character == ' ')) {
            destination[0] = 0;
            return;
        }
    }
    strlcpy(destination, value, size);
}

static void make_board_text_font_safe(char *text)
{
    const unsigned char *source = (const unsigned char *)text;
    unsigned char *destination = (unsigned char *)text;
    while (*source != '\0') {
        if (source[0] == 0xE2 && source[1] == 0x80 && (source[2] == 0x98 || source[2] == 0x99)) {
            *destination++ = '\'';
            source += 3;
        } else if (source[0] == 0xE2 && source[1] == 0x80 && (source[2] == 0x9C || source[2] == 0x9D)) {
            *destination++ = '"';
            source += 3;
        } else if (source[0] == 0xE2 && source[1] == 0x80 && (source[2] == 0x93 || source[2] == 0x94)) {
            *destination++ = '-';
            source += 3;
        } else if (source[0] == 0xE2 && source[1] == 0x80 && source[2] == 0xA6) {
            *destination++ = '.';
            *destination++ = '.';
            *destination++ = '.';
            source += 3;
        } else if ((source[0] == 0xE2 && source[1] == 0x80 && source[2] == 0xA2)
            || (source[0] == 0xC2 && source[1] == 0xB7)) {
            *destination++ = '/';
            source += source[0] == 0xE2 ? 3 : 2;
        } else if (source[0] == 0xC2 && source[1] == 0xA0) {
            *destination++ = ' ';
            source += 2;
        } else if (source[0] == 0xC3 && source[1] >= 0x80 && source[1] <= 0xBF) {
            static const char latin1_base[] = {
                'A','A','A','A','A','A','A','C','E','E','E','E','I','I','I','I',
                'D','N','O','O','O','O','O', 0 ,'O','U','U','U','U','Y', 0 ,'s',
                'a','a','a','a','a','a','a','c','e','e','e','e','i','i','i','i',
                'd','n','o','o','o','o','o', 0 ,'o','u','u','u','u','y', 0 ,'y',
            };
            char mapped = latin1_base[source[1] - 0x80];
            if (mapped != 0) *destination++ = (unsigned char)mapped;
            source += 2;
        } else if (*source >= 0x20 && *source <= 0x7E) {
            *destination++ = *source++;
        } else if (*source < 0x80) {
            if (*source == '\n' || *source == '\r' || *source == '\t') *destination++ = ' ';
            ++source;
        } else {
            size_t sequence = (*source & 0xE0) == 0xC0 ? 2
                : ((*source & 0xF0) == 0xE0 ? 3 : ((*source & 0xF8) == 0xF0 ? 4 : 1));
            while (sequence-- > 0 && *source != '\0') ++source;
        }
    }
    *destination = '\0';
}

static void copy_json_board_text(cJSON *object, const char *name, char *destination, size_t size)
{
    copy_json_string(object, name, destination, size);
    make_board_text_font_safe(destination);
}

static bool parse_snapshot(cJSON *message, dashboard_model_t *model)
{
    cJSON *type = cJSON_GetObjectItemCaseSensitive(message, "type");
    cJSON *snapshot = cJSON_GetObjectItemCaseSensitive(message, "snapshot");
    cJSON *tasks = cJSON_GetObjectItemCaseSensitive(snapshot, "tasks");
    if (!cJSON_IsString(type) || strcmp(type->valuestring, "snapshot") != 0 || !cJSON_IsArray(tasks)) {
        return false;
    }
    memset(model, 0, sizeof(*model));
    cJSON *revision = cJSON_GetObjectItemCaseSensitive(snapshot, "revision");
    model->revision = cJSON_IsNumber(revision) ? (uint64_t)revision->valuedouble : 0;
    copy_json_software_version(
        snapshot,
        "companionVersion",
        model->companion_version,
        sizeof(model->companion_version)
    );
    cJSON *host_time = cJSON_GetObjectItemCaseSensitive(snapshot, "hostTime");
    if (cJSON_IsObject(host_time)) {
        cJSON *utc_offset = cJSON_GetObjectItemCaseSensitive(host_time, "utcOffsetSeconds");
        cJSON *timezone = cJSON_GetObjectItemCaseSensitive(host_time, "timezoneAbbreviation");
        bool timezone_valid = cJSON_IsString(timezone)
            && timezone->valuestring[0] != 0
            && strlen(timezone->valuestring) < sizeof(model->timezone_abbreviation);
        if (timezone_valid) {
            for (const unsigned char *character = (const unsigned char *)timezone->valuestring;
                 *character != 0;
                 ++character) {
                if (!((*character >= 'A' && *character <= 'Z')
                    || (*character >= 'a' && *character <= 'z')
                    || (*character >= '0' && *character <= '9')
                    || *character == '+' || *character == '-' || *character == ':')) {
                    timezone_valid = false;
                    break;
                }
            }
        }
        int offset = cJSON_IsNumber(utc_offset) ? (int)utc_offset->valuedouble : 0;
        if (timezone_valid
            && cJSON_IsNumber(utc_offset)
            && utc_offset->valuedouble == (double)offset
            && offset >= -50400 && offset <= 50400) {
            model->host_time_available = true;
            model->utc_offset_seconds = offset;
            strlcpy(model->timezone_abbreviation, timezone->valuestring, sizeof(model->timezone_abbreviation));
        }
    }
    cJSON *mac_power = cJSON_GetObjectItemCaseSensitive(snapshot, "macPower");
    if (cJSON_IsObject(mac_power)) {
        cJSON *level = cJSON_GetObjectItemCaseSensitive(mac_power, "levelPercent");
        cJSON *state = cJSON_GetObjectItemCaseSensitive(mac_power, "state");
        int level_value = cJSON_IsNumber(level)
            && level->valuedouble >= 0.0 && level->valuedouble <= 100.0
            ? (int)level->valuedouble
            : -1;
        if (level_value >= 0
            && level->valuedouble == (double)level_value
            && cJSON_IsString(state)
            && mac_power_state(state->valuestring, &model->mac_power_state)) {
            model->mac_power_available = true;
            model->mac_power_percent = (uint8_t)level_value;
        }
    }
    cJSON *weather_location = cJSON_GetObjectItemCaseSensitive(snapshot, "weatherLocation");
    if (cJSON_IsObject(weather_location)) {
        cJSON *name = cJSON_GetObjectItemCaseSensitive(weather_location, "name");
        cJSON *latitude = cJSON_GetObjectItemCaseSensitive(weather_location, "latitude");
        cJSON *longitude = cJSON_GetObjectItemCaseSensitive(weather_location, "longitude");
        if (cJSON_IsString(name) && name->valuestring[0] != 0 && strlen(name->valuestring) <= 40
            && cJSON_IsNumber(latitude) && cJSON_IsNumber(longitude)) {
            strlcpy(model->weather_location_name, name->valuestring, sizeof(model->weather_location_name));
            make_board_text_font_safe(model->weather_location_name);
            if (model->weather_location_name[0] != 0) {
                model->weather_location_available = true;
                model->weather_latitude = latitude->valuedouble;
                model->weather_longitude = longitude->valuedouble;
            }
        }
    }
    cJSON *task = NULL;
    cJSON_ArrayForEach(task, tasks) {
        if (model->task_count >= DASHBOARD_MAX_TASKS) break;
        dashboard_task_t *target = &model->tasks[model->task_count++];
        copy_json_string(task, "id", target->id, sizeof(target->id));
        copy_json_board_text(task, "title", target->title, sizeof(target->title));
        copy_json_board_text(task, "shortSummary", target->summary, sizeof(target->summary));
        cJSON *state = cJSON_GetObjectItemCaseSensitive(task, "state");
        cJSON *attention_item = cJSON_GetObjectItemCaseSensitive(task, "attentionKind");
        target->state = task_state(cJSON_IsString(state) ? state->valuestring : NULL);
        target->attention = attention(cJSON_IsString(attention_item) ? attention_item->valuestring : NULL);
    }
    cJSON *capabilities = cJSON_GetObjectItemCaseSensitive(snapshot, "capabilities");
    bool legacy_codex_enabled = false;
    if (cJSON_IsArray(capabilities)) {
        cJSON *capability = NULL;
        cJSON_ArrayForEach(capability, capabilities) {
            if (!cJSON_IsString(capability)) continue;
            if (strcmp(capability->valuestring, "tasks.read") == 0) {
                legacy_codex_enabled = true;
            } else if (strcmp(capability->valuestring, "tasks.continue.fixed") == 0) {
                model->codex_continue_enabled = true;
            }
        }
    }
    cJSON *codex_enabled = cJSON_GetObjectItemCaseSensitive(snapshot, "codexEnabled");
    model->codex_enabled = cJSON_IsTrue(codex_enabled)
        || (!cJSON_IsBool(codex_enabled) && legacy_codex_enabled);
    if (!model->codex_enabled) {
        model->task_count = 0;
        model->codex_continue_enabled = false;
    }
    cJSON *news_feed = cJSON_GetObjectItemCaseSensitive(snapshot, "newsFeed");
    cJSON *x_news_enabled = cJSON_GetObjectItemCaseSensitive(snapshot, "xNewsEnabled");
    model->x_news_enabled = cJSON_IsTrue(x_news_enabled)
        || (!cJSON_IsBool(x_news_enabled) && cJSON_IsObject(news_feed));
    cJSON *stories = cJSON_GetObjectItemCaseSensitive(news_feed, "stories");
    if (cJSON_IsArray(stories)) {
        cJSON *story = NULL;
        cJSON_ArrayForEach(story, stories) {
            if (model->news_count >= DASHBOARD_MAX_NEWS) break;
            dashboard_news_story_t *target = &model->news[model->news_count++];
            copy_json_string(story, "category", target->category, sizeof(target->category));
            copy_json_board_text(story, "headline", target->headline, sizeof(target->headline));
            copy_json_board_text(story, "summary", target->summary, sizeof(target->summary));
            copy_json_string(story, "confidence", target->confidence, sizeof(target->confidence));
            cJSON *sources = cJSON_GetObjectItemCaseSensitive(story, "sources");
            cJSON *source = cJSON_IsArray(sources) ? cJSON_GetArrayItem(sources, 0) : NULL;
            if (cJSON_IsObject(source)) {
                copy_json_string(source, "handle", target->handle, sizeof(target->handle));
            }
        }
    }
    return true;
}

static bool channel_is_active(mac_channel_kind_t kind, uint32_t generation)
{
    portENTER_CRITICAL(&refresh_lock);
    bool active = active_channel_present
        && active_channel_kind == kind
        && active_channel_generation == generation;
    portEXIT_CRITICAL(&refresh_lock);
    return active;
}

static bool claim_channel(mac_channel_kind_t kind, uint32_t *generation)
{
    portENTER_CRITICAL(&refresh_lock);
    bool accepted = kind == MAC_CHANNEL_WIFI || !active_channel_present;
    if (accepted) {
        active_channel_kind = kind;
        active_channel_present = true;
        active_channel_generation += 1;
        transport_online = false;
        *generation = active_channel_generation;
    }
    portEXIT_CRITICAL(&refresh_lock);
    if (accepted) dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_CONNECTING);
    return accepted;
}

static bool usb_channel_can_start(void)
{
    portENTER_CRITICAL(&refresh_lock);
    bool allowed = !active_channel_present;
    portEXIT_CRITICAL(&refresh_lock);
    return allowed;
}

static void release_channel(mac_channel_kind_t kind, uint32_t generation)
{
    portENTER_CRITICAL(&refresh_lock);
    bool releasing_active = active_channel_present
        && active_channel_kind == kind
        && active_channel_generation == generation;
    bool chat_was_pending = false;
    bool continue_was_pending = false;
    if (releasing_active) {
        active_channel_present = false;
        transport_online = false;
        x_news_refresh_requested = false;
        codex_chat_supported = false;
        chat_was_pending = codex_chat_requested || codex_chat_in_flight;
        codex_chat_requested = false;
        codex_chat_in_flight = false;
        continue_was_pending = codex_continue_requested || codex_continue_in_flight;
        codex_continue_requested = false;
        codex_continue_in_flight = false;
    }
    portEXIT_CRITICAL(&refresh_lock);
    if (!releasing_active) return;
    if (continue_was_pending) dashboard_ui_set_codex_continue_state(DASHBOARD_CODEX_CONTINUE_FAILED);
    if (chat_was_pending) dashboard_ui_set_codex_chat_detail(NULL);
    dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_OFFLINE);
}

static void run_protocol_session(
    mac_channel_t *channel,
    mac_transport_config_t *config,
    uint32_t generation
)
{
    cJSON *hello = cJSON_CreateObject();
    cJSON_AddStringToObject(hello, "type", "hello");
    cJSON_AddNumberToObject(hello, "protocolVersion", 1);
    cJSON_AddStringToObject(hello, "boardID", config->board_id);
    cJSON_AddStringToObject(hello, "firmwareVersion", esp_app_get_description()->version);
    cJSON *capabilities = cJSON_AddArrayToObject(hello, "capabilities");
    if (capabilities != NULL) {
        cJSON_AddItemToArray(capabilities, cJSON_CreateString("tasks.read"));
        cJSON_AddItemToArray(capabilities, cJSON_CreateString("tasks.chat.read"));
        cJSON_AddItemToArray(capabilities, cJSON_CreateString("tasks.continue.fixed"));
        cJSON_AddItemToArray(capabilities, cJSON_CreateString("display.capture.rgb565"));
        cJSON_AddItemToArray(capabilities, cJSON_CreateString("xNews.refresh.request"));
#if CONFIG_ILO_OTA_DELIVERY
        cJSON_AddItemToArray(capabilities, cJSON_CreateString("firmware.update.signed"));
#endif
    }
    bool ok = channel_is_active(channel->kind, generation) && channel_send_json(channel, hello);
    cJSON_Delete(hello);
    cJSON *reply = ok ? channel_read_json(channel) : NULL;
    cJSON *reply_type = reply != NULL ? cJSON_GetObjectItemCaseSensitive(reply, "type") : NULL;
    ok = channel_is_active(channel->kind, generation)
        && cJSON_IsString(reply_type)
        && strcmp(reply_type->valuestring, "helloAck") == 0;
    cJSON *reply_capabilities = reply != NULL
        ? cJSON_GetObjectItemCaseSensitive(reply, "capabilities") : NULL;
    bool supports_chat = ok && json_array_contains_string(reply_capabilities, "tasks.chat.read");
    if (ok && channel->kind == MAC_CHANNEL_USB) {
        cJSON *host_address = cJSON_GetObjectItemCaseSensitive(reply, "hostAddress");
        cJSON *host_port = cJSON_GetObjectItemCaseSensitive(reply, "hostPort");
        if (cJSON_IsString(host_address) && cJSON_IsNumber(host_port)
            && host_port->valuedouble >= 1 && host_port->valuedouble <= 65535) {
            (void)save_host_endpoint(config, host_address->valuestring, (uint16_t)host_port->valuedouble);
        }
    }
    cJSON_Delete(reply);
    if (ok) {
        cJSON *subscribe = cJSON_CreateObject();
        cJSON_AddStringToObject(subscribe, "type", "subscribe");
        ok = channel_send_json(channel, subscribe);
        cJSON_Delete(subscribe);
    }
    if (!ok || !channel_is_active(channel->kind, generation)) return;

    portENTER_CRITICAL(&refresh_lock);
    codex_chat_supported = supports_chat;
    transport_online = true;
    if (ota_status_pending.current_version[0] != 0) ota_status_dirty = true;
    portEXIT_CRITICAL(&refresh_lock);
    dashboard_ui_set_connection_state(
        channel->kind == MAC_CHANNEL_USB ? DASHBOARD_CONNECTION_USB : DASHBOARD_CONNECTION_ONLINE
    );
    ESP_LOGI(TAG, "Paired Mac connected over %s", channel->kind == MAC_CHANNEL_USB ? "USB" : "Wi-Fi");

    for (;;) {
        if (!channel_is_active(channel->kind, generation)) break;
        if (!send_pending_ota_status(channel)) break;
        if (take_x_news_refresh_request() && !send_x_news_refresh_request(channel)) break;
        char chat_task_id[CODEX_TASK_ID_MAX + 1];
        char chat_request_id[sizeof(codex_chat_request_id)];
        if (take_codex_chat_request(
                chat_task_id,
                sizeof(chat_task_id),
                chat_request_id,
                sizeof(chat_request_id)
            ) && !send_codex_chat_request(channel, chat_task_id, chat_request_id)) {
            dashboard_ui_set_codex_chat_detail(NULL);
            break;
        }
        char continue_task_id[CODEX_TASK_ID_MAX + 1];
        char continue_request_id[sizeof(codex_continue_request_id)];
        if (take_codex_continue_request(
                continue_task_id,
                sizeof(continue_task_id),
                continue_request_id,
                sizeof(continue_request_id)
            ) && !send_codex_continue_request(channel, continue_task_id, continue_request_id)) {
            dashboard_ui_set_codex_continue_state(DASHBOARD_CODEX_CONTINUE_FAILED);
            break;
        }
        int data_ready = channel_wait_data(channel, 250);
        if (data_ready < 0) break;
        if (data_ready == 0) continue;
        cJSON *message = channel_read_json(channel);
        if (message == NULL) break;
        cJSON *message_type = cJSON_GetObjectItemCaseSensitive(message, "type");
        if (cJSON_IsString(message_type)
            && strcmp(message_type->valuestring, "screenCaptureRequest") == 0) {
            bool capture_ok = handle_capture_request(channel, message);
            cJSON_Delete(message);
            if (!capture_ok) break;
            continue;
        }
        if (cJSON_IsString(message_type)
            && strcmp(message_type->valuestring, "xNewsRefreshStatus") == 0) {
            handle_x_news_refresh_status(message);
            cJSON_Delete(message);
            continue;
        }
        if (cJSON_IsString(message_type)
            && strcmp(message_type->valuestring, "codexChatDetail") == 0) {
            handle_codex_chat_detail(message);
            cJSON_Delete(message);
            continue;
        }
        if (cJSON_IsString(message_type)
            && strcmp(message_type->valuestring, "codexContinueStatus") == 0) {
            handle_codex_continue_status(message);
            cJSON_Delete(message);
            continue;
        }
        if (cJSON_IsString(message_type)
            && strcmp(message_type->valuestring, "firmwareUpdateCommand") == 0) {
            (void)handle_firmware_update_command(message);
            cJSON_Delete(message);
            continue;
        }
        dashboard_model_t *model = heap_caps_malloc(
            sizeof(*model),
            MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT
        );
        if (model == NULL) {
            ESP_LOGE(TAG, "Dashboard snapshot allocation failed");
            cJSON_Delete(message);
            break;
        }
        if (parse_snapshot(message, model) && model_callback != NULL) model_callback(model);
        free(model);
        cJSON_Delete(message);
    }
}

static void transport_task(void *argument)
{
    mac_transport_config_t *config = argument;
    psk_hint_key_t psk = {
        .key = config->psk,
        .key_size = sizeof(config->psk),
        .hint = config->board_id,
    };
    esp_tls_cfg_t tls_config = { .psk_hint_key = &psk, .timeout_ms = 10000 };

    for (;;) {
        xEventGroupWaitBits(wifi_events, WIFI_READY_BIT, pdFALSE, pdTRUE, portMAX_DELAY);
        mac_endpoint_t endpoint = endpoint_for_connection(config);
        esp_tls_t *tls = esp_tls_init();
        if (tls == NULL) {
            vTaskDelay(pdMS_TO_TICKS(5000));
            continue;
        }
        int connected = esp_tls_conn_new_sync(
            endpoint.address,
            strlen(endpoint.address),
            endpoint.port,
            &tls_config,
            tls
        );
        if (connected == 1) {
            uint32_t generation = 0;
            if (claim_channel(MAC_CHANNEL_WIFI, &generation)) {
                mac_channel_t channel = {
                    .context = tls,
                    .send_json = tls_channel_send_json,
                    .read_json = tls_channel_read_json,
                    .wait_data = tls_channel_wait_data,
                    .kind = MAC_CHANNEL_WIFI,
                };
                run_protocol_session(&channel, config, generation);
                release_channel(MAC_CHANNEL_WIFI, generation);
            }
        }
        esp_tls_conn_destroy(tls);
        vTaskDelay(pdMS_TO_TICKS(5000));
    }
}

static void usb_transport_task(void *argument)
{
    mac_transport_config_t *config = argument;
    for (;;) {
        if (!usb_channel_can_start()) {
            vTaskDelay(pdMS_TO_TICKS(500));
            continue;
        }
        usb_secure_channel_t usb = { 0 };
        if (!usb_secure_channel_accept(&usb, config->board_id, config->psk)) {
            usb_secure_channel_close(&usb);
            vTaskDelay(pdMS_TO_TICKS(1000));
            continue;
        }
        uint32_t generation = 0;
        if (claim_channel(MAC_CHANNEL_USB, &generation)) {
            mac_channel_t channel = {
                .context = &usb,
                .send_json = usb_channel_send_json,
                .read_json = usb_channel_read_json,
                .wait_data = usb_channel_wait_data,
                .kind = MAC_CHANNEL_USB,
            };
            run_protocol_session(&channel, config, generation);
            release_channel(MAC_CHANNEL_USB, generation);
        }
        usb_secure_channel_close(&usb);
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

void mac_transport_publish_ota_status(const ota_updater_status_t *status)
{
    if (status == NULL) return;
    portENTER_CRITICAL(&refresh_lock);
    ota_status_pending = *status;
    ota_status_dirty = true;
    portEXIT_CRITICAL(&refresh_lock);
}

bool mac_transport_request_x_news_refresh(void)
{
    portENTER_CRITICAL(&refresh_lock);
    bool accepted = transport_online && !x_news_refresh_requested;
    if (accepted) x_news_refresh_requested = true;
    portEXIT_CRITICAL(&refresh_lock);
    ESP_LOGI(TAG, "X News refresh gesture %s", accepted ? "queued" : "not queued");
    return accepted;
}

bool mac_transport_request_codex_chat(const char *task_id)
{
    if (task_id == NULL) return false;
    size_t task_id_size = strlen(task_id);
    if (task_id_size == 0 || task_id_size > CODEX_TASK_ID_MAX) return false;
    for (size_t index = 0; index < task_id_size; ++index) {
        char character = task_id[index];
        if (!((character >= 'a' && character <= 'z')
            || (character >= 'A' && character <= 'Z')
            || (character >= '0' && character <= '9')
            || character == '-')) {
            return false;
        }
    }

    portENTER_CRITICAL(&refresh_lock);
    bool accepted = transport_online && codex_chat_supported
        && !codex_chat_requested && !codex_chat_in_flight;
    if (accepted) {
        strlcpy(codex_chat_task_id, task_id, sizeof(codex_chat_task_id));
        snprintf(
            codex_chat_request_id,
            sizeof(codex_chat_request_id),
            "board-%08lx-%08lx",
            (unsigned long)esp_random(),
            (unsigned long)esp_random()
        );
        codex_chat_requested = true;
    }
    portEXIT_CRITICAL(&refresh_lock);
    ESP_LOGI(TAG, "Codex chat detail %s", accepted ? "queued" : "not available");
    return accepted;
}

bool mac_transport_request_codex_continue(const char *task_id)
{
    if (task_id == NULL) return false;
    size_t task_id_size = strlen(task_id);
    if (task_id_size == 0 || task_id_size > CODEX_TASK_ID_MAX) return false;
    for (size_t index = 0; index < task_id_size; ++index) {
        char character = task_id[index];
        if (!((character >= 'a' && character <= 'z')
            || (character >= 'A' && character <= 'Z')
            || (character >= '0' && character <= '9')
            || character == '-')) {
            return false;
        }
    }

    portENTER_CRITICAL(&refresh_lock);
    bool accepted = transport_online && !codex_continue_requested && !codex_continue_in_flight;
    if (accepted) {
        strlcpy(codex_continue_task_id, task_id, sizeof(codex_continue_task_id));
        snprintf(
            codex_continue_request_id,
            sizeof(codex_continue_request_id),
            "board-%08lx-%08lx",
            (unsigned long)esp_random(),
            (unsigned long)esp_random()
        );
        codex_continue_requested = true;
    }
    portEXIT_CRITICAL(&refresh_lock);
    ESP_LOGI(TAG, "Codex continue action %s", accepted ? "queued" : "not queued");
    return accepted;
}

bool mac_transport_start(mac_transport_model_callback_t callback)
{
    model_callback = callback;
    mac_transport_config_t *config = calloc(1, sizeof(*config));
    if (config == NULL) {
        return false;
    }
    esp_err_t status = load_config(config);
    if (status != ESP_OK) {
        free(config);
        ESP_LOGI(TAG, "No valid runtime provisioning found in NVS");
        return false;
    }
    if (wifi_start(config) != ESP_OK) {
        free(config);
        return false;
    }
    esp_err_t usb_status = usb_secure_channel_initialize();
    if (usb_status != ESP_OK) {
        ESP_LOGW(TAG, "USB fallback unavailable: %s", esp_err_to_name(usb_status));
    }
    esp_err_t mdns_status = mdns_init();
    mdns_available = mdns_status == ESP_OK;
    if (!mdns_available) {
        ESP_LOGW(TAG, "Bonjour unavailable: %s; provisioned host fallback remains active", esp_err_to_name(mdns_status));
    }
    dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_CONNECTING);
    if (xTaskCreatePinnedToCore(transport_task, "mac_transport", 8192, config, 5, NULL, 0) != pdPASS) {
        free(config);
        return false;
    }
    if (usb_status == ESP_OK
        && xTaskCreatePinnedToCore(usb_transport_task, "usb_transport", 6144, config, 5, NULL, 0) != pdPASS) {
        ESP_LOGW(TAG, "USB fallback task could not start; Wi-Fi transport remains active");
    }
    return true;
}

bool mac_transport_update_wifi(const char *ssid, const char *password)
{
    if (wifi_events == NULL || ssid == NULL || password == NULL) return false;
    size_t ssid_size = strlen(ssid);
    size_t password_size = strlen(password);
    if (ssid_size == 0 || ssid_size > 32 || password_size < 8 || password_size > 63) return false;
    if (wifi_control_mutex == NULL
        || xSemaphoreTake(wifi_control_mutex, portMAX_DELAY) != pdTRUE) return false;

    wifi_config_t config = { 0 };
    memcpy(config.sta.ssid, ssid, ssid_size);
    memcpy(config.sta.password, password, password_size);
    config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;

    wifi_config_t previous_config = { 0 };
    esp_err_t status = esp_wifi_get_config(WIFI_IF_STA, &previous_config);
    if (status != ESP_OK) {
        xSemaphoreGive(wifi_control_mutex);
        return false;
    }

    portENTER_CRITICAL(&refresh_lock);
    wifi_update_in_progress = true;
    wifi_reconnect_suspended = true;
    portEXIT_CRITICAL(&refresh_lock);
    (void)esp_wifi_scan_stop();
    status = esp_wifi_stop();
    if (status == ESP_OK) status = esp_wifi_set_config(WIFI_IF_STA, &config);

    nvs_handle_t handle = 0;
    if (status == ESP_OK) status = nvs_open("ilo_board", NVS_READWRITE, &handle);
    if (status == ESP_OK) status = nvs_set_str(handle, "wifi_ssid", ssid);
    if (status == ESP_OK) status = nvs_set_str(handle, "wifi_password", password);
    if (status == ESP_OK) status = nvs_commit(handle);
    if (handle != 0) nvs_close(handle);
    if (status != ESP_OK) {
        (void)esp_wifi_set_config(WIFI_IF_STA, &previous_config);
    }

    portENTER_CRITICAL(&refresh_lock);
    wifi_update_in_progress = false;
    wifi_reconnect_suspended = false;
    portEXIT_CRITICAL(&refresh_lock);
    esp_err_t start_status = esp_wifi_start();
    xSemaphoreGive(wifi_control_mutex);
    if (status != ESP_OK || start_status != ESP_OK) {
        ESP_LOGE(
            TAG,
            "Wi-Fi update failed: config=%s start=%s",
            esp_err_to_name(status),
            esp_err_to_name(start_status)
        );
        return false;
    }
    dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_CONNECTING);
    ESP_LOGI(TAG, "Saved new Wi-Fi credentials; reconnecting");
    return true;
}

size_t mac_transport_scan_wifi(char (*ssids)[33], size_t maximum_count)
{
    if (wifi_events == NULL || ssids == NULL || maximum_count == 0) return 0;
    portENTER_CRITICAL(&refresh_lock);
    size_t available = wifi_scan_count;
    if (available > maximum_count) available = maximum_count;
    for (size_t index = 0; index < available; ++index) {
        strlcpy(ssids[index], wifi_scan_ssids[index], 33);
    }
    TickType_t now = xTaskGetTickCount();
    bool cooldown_elapsed = !wifi_scan_requested_once
        || (now - wifi_scan_last_started) >= pdMS_TO_TICKS(30000);
    bool should_start = !wifi_scan_in_progress && cooldown_elapsed && wifi_scan_task_handle != NULL;
    if (should_start) {
        wifi_scan_in_progress = true;
        wifi_scan_requested_once = true;
        wifi_scan_last_started = now;
    }
    portEXIT_CRITICAL(&refresh_lock);
    if (should_start) xTaskNotifyGive(wifi_scan_task_handle);
    return available;
}

bool mac_transport_start_wifi_only(void)
{
    mac_transport_config_t config = { 0 };
    load_wifi_config(&config);
    return wifi_start(&config) == ESP_OK;
}

bool mac_transport_wait_for_network(uint32_t timeout_ms)
{
    if (wifi_events == NULL) {
        return false;
    }
    EventBits_t bits = xEventGroupWaitBits(
        wifi_events,
        WIFI_READY_BIT,
        pdFALSE,
        pdTRUE,
        pdMS_TO_TICKS(timeout_ms)
    );
    return (bits & WIFI_READY_BIT) != 0;
}
