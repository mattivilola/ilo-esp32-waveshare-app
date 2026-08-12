#include "weather_client.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>

#include "cJSON.h"
#include "clock_sync.h"
#include "esp_crt_bundle.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mac_transport.h"
#include "nvs.h"

#define RESPONSE_CAPACITY 8192
#define REFRESH_INTERVAL_MS (30U * 60U * 1000U)
#define RETRY_INTERVAL_MS (60U * 1000U)

typedef struct {
    char location[41];
    char latitude[17];
    char longitude[17];
} weather_config_t;

typedef struct {
    char data[RESPONSE_CAPACITY];
    size_t used;
    bool overflow;
} response_buffer_t;

static const char *TAG = "weather_client";
static weather_model_callback_t model_callback;
static TaskHandle_t weather_task_handle;
static portMUX_TYPE config_lock = portMUX_INITIALIZER_UNLOCKED;
static weather_config_t active_config;
static bool active_config_valid;

static esp_err_t nvs_string(nvs_handle_t handle, const char *key, char *destination, size_t size)
{
    size_t required = size;
    return nvs_get_str(handle, key, destination, &required);
}

static bool load_weather_config(weather_config_t *config)
{
    nvs_handle_t handle;
    if (nvs_open("ilo_board", NVS_READONLY, &handle) != ESP_OK) return false;
    esp_err_t status = nvs_string(handle, "weather_name", config->location, sizeof(config->location));
    if (status == ESP_OK) status = nvs_string(handle, "weather_lat", config->latitude, sizeof(config->latitude));
    if (status == ESP_OK) status = nvs_string(handle, "weather_lon", config->longitude, sizeof(config->longitude));
    nvs_close(handle);
    return status == ESP_OK && config->location[0] != 0 && config->latitude[0] != 0 && config->longitude[0] != 0;
}

static bool save_weather_config(const weather_config_t *config)
{
    nvs_handle_t handle;
    esp_err_t status = nvs_open("ilo_board", NVS_READWRITE, &handle);
    if (status != ESP_OK) return false;
    if (status == ESP_OK) status = nvs_set_str(handle, "weather_name", config->location);
    if (status == ESP_OK) status = nvs_set_str(handle, "weather_lat", config->latitude);
    if (status == ESP_OK) status = nvs_set_str(handle, "weather_lon", config->longitude);
    if (status == ESP_OK) status = nvs_commit(handle);
    nvs_close(handle);
    return status == ESP_OK;
}

static esp_err_t http_event(esp_http_client_event_t *event)
{
    response_buffer_t *buffer = event->user_data;
    if (event->event_id != HTTP_EVENT_ON_DATA || buffer == NULL || event->data_len <= 0) return ESP_OK;
    size_t incoming = (size_t)event->data_len;
    if (incoming > sizeof(buffer->data) - buffer->used - 1) {
        buffer->overflow = true;
        return ESP_FAIL;
    }
    memcpy(buffer->data + buffer->used, event->data, incoming);
    buffer->used += incoming;
    buffer->data[buffer->used] = 0;
    return ESP_OK;
}

static bool number(cJSON *object, const char *key, float *value)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(object, key);
    if (!cJSON_IsNumber(item)) return false;
    *value = (float)item->valuedouble;
    return true;
}

static bool integer(cJSON *object, const char *key, int *value)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(object, key);
    if (!cJSON_IsNumber(item)) return false;
    *value = item->valueint;
    return true;
}

static bool parse_weather(const char *json, weather_model_t *model)
{
    cJSON *root = cJSON_Parse(json);
    if (root == NULL) return false;
    cJSON *current = cJSON_GetObjectItemCaseSensitive(root, "current");
    cJSON *daily = cJSON_GetObjectItemCaseSensitive(root, "daily");
    cJSON *utc_offset = cJSON_GetObjectItemCaseSensitive(root, "utc_offset_seconds");
    cJSON *timezone_abbreviation = cJSON_GetObjectItemCaseSensitive(root, "timezone_abbreviation");
    bool ok = cJSON_IsObject(current) && cJSON_IsObject(daily)
        && cJSON_IsNumber(utc_offset)
        && cJSON_IsString(timezone_abbreviation)
        && number(current, "temperature_2m", &model->temperature_c)
        && number(current, "apparent_temperature", &model->apparent_c)
        && number(current, "wind_speed_10m", &model->wind_ms)
        && integer(current, "weather_code", &model->weather_code);

    if (ok) {
        model->utc_offset_seconds = (int32_t)utc_offset->valuedouble;
        strlcpy(
            model->timezone_abbreviation,
            timezone_abbreviation->valuestring,
            sizeof(model->timezone_abbreviation)
        );
    }

    cJSON *codes = cJSON_GetObjectItemCaseSensitive(daily, "weather_code");
    cJSON *maximums = cJSON_GetObjectItemCaseSensitive(daily, "temperature_2m_max");
    cJSON *minimums = cJSON_GetObjectItemCaseSensitive(daily, "temperature_2m_min");
    if (!cJSON_IsArray(codes) || !cJSON_IsArray(maximums) || !cJSON_IsArray(minimums)) ok = false;
    model->day_count = 0;
    if (ok) {
        int available = cJSON_GetArraySize(codes);
        for (int index = 0; index < WEATHER_FORECAST_DAYS && index < available; ++index) {
            cJSON *code = cJSON_GetArrayItem(codes, index);
            cJSON *maximum = cJSON_GetArrayItem(maximums, index);
            cJSON *minimum = cJSON_GetArrayItem(minimums, index);
            if (!cJSON_IsNumber(code) || !cJSON_IsNumber(maximum) || !cJSON_IsNumber(minimum)) break;
            model->days[model->day_count++] = (weather_day_t) {
                .weather_code = code->valueint,
                .maximum_c = (float)maximum->valuedouble,
                .minimum_c = (float)minimum->valuedouble,
            };
        }
        ok = model->day_count == WEATHER_FORECAST_DAYS;
    }
    cJSON_Delete(root);
    return ok;
}

static bool fetch_weather(const weather_config_t *weather_config, weather_model_t *model)
{
    char url[768];
    int length = snprintf(
        url,
        sizeof(url),
        "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s"
        "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m"
        "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        "&timezone=auto&forecast_days=3&wind_speed_unit=ms",
        weather_config->latitude,
        weather_config->longitude
    );
    if (length <= 0 || (size_t)length >= sizeof(url)) return false;

    response_buffer_t response = { 0 };
    esp_http_client_config_t config = {
        .url = url,
        .user_agent = "ILOBoard/0.1",
        .event_handler = http_event,
        .user_data = &response,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 10000,
        .buffer_size = 2048,
    };
    esp_http_client_handle_t client = esp_http_client_init(&config);
    if (client == NULL) return false;
    esp_err_t status = esp_http_client_perform(client);
    int http_status = esp_http_client_get_status_code(client);
    esp_http_client_cleanup(client);
    if (status != ESP_OK || http_status != 200 || response.overflow || response.used == 0) {
        ESP_LOGW(TAG, "Weather request failed: %s, HTTP %d", esp_err_to_name(status), http_status);
        return false;
    }
    return parse_weather(response.data, model);
}

static void publish(const weather_model_t *model)
{
    if (model_callback != NULL) model_callback(model);
}

static void weather_task(void *argument)
{
    (void)argument;
    weather_model_t model = { .state = WEATHER_STATE_LOADING };

    for (;;) {
        weather_config_t config;
        taskENTER_CRITICAL(&config_lock);
        config = active_config;
        bool configured = active_config_valid;
        taskEXIT_CRITICAL(&config_lock);
        if (!configured) {
            model = (weather_model_t) { .state = WEATHER_STATE_NOT_CONFIGURED };
            strlcpy(model.location, "Weather setup needed", sizeof(model.location));
            publish(&model);
            ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
            continue;
        }
        model.state = WEATHER_STATE_LOADING;
        strlcpy(model.location, config.location, sizeof(model.location));
        publish(&model);
        if (!mac_transport_wait_for_network(30000)) {
            ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(RETRY_INTERVAL_MS));
            continue;
        }
        bool ok = clock_sync_wait(15000) && fetch_weather(&config, &model);
        if (ok) {
            model.state = WEATHER_STATE_LIVE;
            model.updated_epoch = (int64_t)time(NULL);
        } else {
            model.state = model.updated_epoch > 0 ? WEATHER_STATE_STALE : WEATHER_STATE_ERROR;
        }
        publish(&model);
        ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(ok ? REFRESH_INTERVAL_MS : RETRY_INTERVAL_MS));
    }
}

bool weather_client_start(weather_model_callback_t callback)
{
    model_callback = callback;
    weather_config_t config = { 0 };
    active_config_valid = load_weather_config(&config);
    if (active_config_valid) active_config = config;
    if (xTaskCreatePinnedToCore(weather_task, "weather", 8192, NULL, 3, &weather_task_handle, 0) != pdPASS) {
        weather_task_handle = NULL;
        return false;
    }
    return true;
}

bool weather_client_update_location(const char *name, double latitude, double longitude)
{
    if (name == NULL || name[0] == 0 || strlen(name) > 40
        || !isfinite(latitude) || latitude < -90.0 || latitude > 90.0
        || !isfinite(longitude) || longitude < -180.0 || longitude > 180.0) {
        return false;
    }
    weather_config_t config = { 0 };
    strlcpy(config.location, name, sizeof(config.location));
    if (snprintf(config.latitude, sizeof(config.latitude), "%.2f", latitude) <= 0
        || snprintf(config.longitude, sizeof(config.longitude), "%.2f", longitude) <= 0) {
        return false;
    }
    taskENTER_CRITICAL(&config_lock);
    bool unchanged = active_config_valid
        && strcmp(active_config.location, config.location) == 0
        && strcmp(active_config.latitude, config.latitude) == 0
        && strcmp(active_config.longitude, config.longitude) == 0;
    taskEXIT_CRITICAL(&config_lock);
    if (unchanged) return true;
    if (!save_weather_config(&config)) return false;
    taskENTER_CRITICAL(&config_lock);
    active_config = config;
    active_config_valid = true;
    taskEXIT_CRITICAL(&config_lock);
    if (weather_task_handle != NULL) xTaskNotifyGive(weather_task_handle);
    ESP_LOGI(TAG, "Weather location updated from authenticated companion");
    return true;
}
