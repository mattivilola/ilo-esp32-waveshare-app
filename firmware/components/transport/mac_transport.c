#include "mac_transport.h"

#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_check.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_tls.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "dashboard_ui.h"

#define WIFI_READY_BIT BIT0
#define FRAME_MAX 65536

static const char *TAG = "mac_transport";
static EventGroupHandle_t wifi_events;
static mac_transport_model_callback_t model_callback;

static void wifi_event(void *argument, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        xEventGroupClearBits(wifi_events, WIFI_READY_BIT);
        dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_OFFLINE);
        esp_wifi_connect();
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        xEventGroupSetBits(wifi_events, WIFI_READY_BIT);
    }
}

static esp_err_t wifi_start(void)
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
    ESP_RETURN_ON_ERROR(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, wifi_event, NULL), TAG, "Wi-Fi handler failed");
    ESP_RETURN_ON_ERROR(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, wifi_event, NULL), TAG, "IP handler failed");

    wifi_config_t config = { 0 };
    strlcpy((char *)config.sta.ssid, CONFIG_ILO_WIFI_SSID, sizeof(config.sta.ssid));
    strlcpy((char *)config.sta.password, CONFIG_ILO_WIFI_PASSWORD, sizeof(config.sta.password));
    config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;
    ESP_RETURN_ON_ERROR(esp_wifi_set_mode(WIFI_MODE_STA), TAG, "Wi-Fi mode failed");
    ESP_RETURN_ON_ERROR(esp_wifi_set_config(WIFI_IF_STA, &config), TAG, "Wi-Fi config failed");
    return esp_wifi_start();
}

static bool decode_hex(const char *input, uint8_t *output, size_t output_size)
{
    if (strlen(input) != output_size * 2) {
        return false;
    }
    for (size_t i = 0; i < output_size; ++i) {
        char byte[3] = { input[i * 2], input[(i * 2) + 1], 0 };
        char *end = NULL;
        long value = strtol(byte, &end, 16);
        if (end == NULL || *end != 0 || value < 0 || value > 255) {
            return false;
        }
        output[i] = (uint8_t)value;
    }
    return true;
}

static bool tls_write_all(esp_tls_t *tls, const uint8_t *data, size_t size)
{
    size_t sent = 0;
    while (sent < size) {
        ssize_t result = esp_tls_conn_write(tls, data + sent, size - sent);
        if (result <= 0) {
            return false;
        }
        sent += (size_t)result;
    }
    return true;
}

static bool tls_read_all(esp_tls_t *tls, uint8_t *data, size_t size)
{
    size_t received = 0;
    while (received < size) {
        ssize_t result = esp_tls_conn_read(tls, data + received, size - received);
        if (result <= 0) {
            return false;
        }
        received += (size_t)result;
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

static void copy_json_string(cJSON *object, const char *name, char *destination, size_t size)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(object, name);
    strlcpy(destination, cJSON_IsString(item) ? item->valuestring : "", size);
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
    cJSON *task = NULL;
    cJSON_ArrayForEach(task, tasks) {
        if (model->task_count >= DASHBOARD_MAX_TASKS) break;
        dashboard_task_t *target = &model->tasks[model->task_count++];
        copy_json_string(task, "id", target->id, sizeof(target->id));
        copy_json_string(task, "title", target->title, sizeof(target->title));
        copy_json_string(task, "shortSummary", target->summary, sizeof(target->summary));
        cJSON *state = cJSON_GetObjectItemCaseSensitive(task, "state");
        cJSON *attention_item = cJSON_GetObjectItemCaseSensitive(task, "attentionKind");
        target->state = task_state(cJSON_IsString(state) ? state->valuestring : NULL);
        target->attention = attention(cJSON_IsString(attention_item) ? attention_item->valuestring : NULL);
    }
    return true;
}

static void transport_task(void *argument)
{
    uint8_t key[32];
    if (!decode_hex(CONFIG_ILO_PSK_HEX, key, sizeof(key))) {
        ESP_LOGE(TAG, "TLS PSK must contain exactly 64 hexadecimal characters");
        vTaskDelete(NULL);
        return;
    }
    psk_hint_key_t psk = { .key = key, .key_size = sizeof(key), .hint = CONFIG_ILO_BOARD_ID };
    esp_tls_cfg_t tls_config = { .psk_hint_key = &psk, .timeout_ms = 10000 };

    for (;;) {
        xEventGroupWaitBits(wifi_events, WIFI_READY_BIT, pdFALSE, pdTRUE, portMAX_DELAY);
        dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_CONNECTING);
        esp_tls_t *tls = esp_tls_init();
        if (tls == NULL) {
            vTaskDelay(pdMS_TO_TICKS(5000));
            continue;
        }
        int connected = esp_tls_conn_new_sync(
            CONFIG_ILO_HOST_ADDRESS,
            strlen(CONFIG_ILO_HOST_ADDRESS),
            CONFIG_ILO_HOST_PORT,
            &tls_config,
            tls
        );
        if (connected == 1) {
            cJSON *hello = cJSON_CreateObject();
            cJSON_AddStringToObject(hello, "type", "hello");
            cJSON_AddNumberToObject(hello, "protocolVersion", 1);
            cJSON_AddStringToObject(hello, "boardID", CONFIG_ILO_BOARD_ID);
            bool ok = send_json(tls, hello);
            cJSON_Delete(hello);
            cJSON *reply = ok ? read_json(tls) : NULL;
            cJSON *reply_type = reply != NULL ? cJSON_GetObjectItemCaseSensitive(reply, "type") : NULL;
            ok = cJSON_IsString(reply_type) && strcmp(reply_type->valuestring, "helloAck") == 0;
            cJSON_Delete(reply);
            if (ok) {
                cJSON *subscribe = cJSON_CreateObject();
                cJSON_AddStringToObject(subscribe, "type", "subscribe");
                ok = send_json(tls, subscribe);
                cJSON_Delete(subscribe);
            }
            if (ok) {
                dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_ONLINE);
                for (;;) {
                    cJSON *message = read_json(tls);
                    if (message == NULL) break;
                    dashboard_model_t model;
                    if (parse_snapshot(message, &model) && model_callback != NULL) {
                        model_callback(&model);
                    }
                    cJSON_Delete(message);
                }
            }
        }
        dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_OFFLINE);
        esp_tls_conn_destroy(tls);
        vTaskDelay(pdMS_TO_TICKS(5000));
    }
}

bool mac_transport_start(mac_transport_model_callback_t callback)
{
    model_callback = callback;
    if (strlen(CONFIG_ILO_WIFI_SSID) == 0 || strlen(CONFIG_ILO_HOST_ADDRESS) == 0
        || CONFIG_ILO_HOST_PORT == 0 || strlen(CONFIG_ILO_PSK_HEX) == 0) {
        return false;
    }
    if (wifi_start() != ESP_OK) {
        return false;
    }
    dashboard_ui_set_connection_state(DASHBOARD_CONNECTION_CONNECTING);
    return xTaskCreatePinnedToCore(transport_task, "mac_transport", 8192, NULL, 5, NULL, 0) == pdPASS;
}
