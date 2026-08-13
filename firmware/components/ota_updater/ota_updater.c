#include "ota_updater.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "cJSON.h"
#include "esp_app_desc.h"
#include "esp_crt_bundle.h"
#include "esp_http_client.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "esp_wifi.h"
#include "mbedtls/base64.h"
#include "mbedtls/pk.h"
#include "mbedtls/rsa.h"
#include "mbedtls/sha256.h"
#include "nvs.h"

#define COMMAND_CHECK BIT0
#define COMMAND_INSTALL BIT1
#define MANIFEST_MAX_BYTES 16384
#define PAYLOAD_MAX_BYTES 8192
#define SIGNATURE_BYTES 384
#define DOWNLOAD_BUFFER_BYTES 4096
#define UPDATER_TASK_STACK_BYTES 16384
#define BOARD_TARGET "waveshare-esp32-s3-touch-lcd-5b-28151"
#define ENVELOPE_SCHEMA "ilo-board-firmware-manifest-envelope-v1"
#define PAYLOAD_SCHEMA "ilo-board-firmware-manifest-v1"
#define SIGNATURE_ALGORITHM "RSA-PSS-SHA256"
#define OTA_NAMESPACE "ilo_ota"

#ifndef CONFIG_ILO_OTA_MANIFEST_URL
#define CONFIG_ILO_OTA_MANIFEST_URL ""
#endif
#ifndef CONFIG_ILO_OTA_RELEASE_URL_PREFIX
#define CONFIG_ILO_OTA_RELEASE_URL_PREFIX ""
#endif

typedef struct {
    char version[32];
    uint32_t sequence;
    char url[256];
    size_t size;
    uint8_t sha256[32];
} verified_manifest_t;

typedef struct {
    uint8_t *bytes;
    size_t length;
    bool overflow;
} response_buffer_t;

static portMUX_TYPE status_lock = portMUX_INITIALIZER_UNLOCKED;
static ota_updater_status_t current_status;
static ota_updater_status_callback_t status_callback;
#if CONFIG_ILO_OTA_DELIVERY
static const char *TAG = "ota_updater";
static EventGroupHandle_t commands;
static verified_manifest_t cached_manifest;
static bool cached_manifest_valid;
static EventGroupHandle_t network_events;
static StaticTask_t updater_task_storage;
static StackType_t updater_task_stack[UPDATER_TASK_STACK_BYTES / sizeof(StackType_t)];
static TaskHandle_t updater_task_handle;
static bool updater_ready;
#define NETWORK_READY BIT0
#endif

#if CONFIG_ILO_OTA_DELIVERY
extern const uint8_t ota_manifest_public_key_start[] asm("_binary_ota_manifest_public_key_pem_start");
extern const uint8_t ota_manifest_public_key_end[] asm("_binary_ota_manifest_public_key_pem_end");
#endif

static void publish_status(ota_updater_state_t state, const char *available, uint8_t progress, const char *detail)
{
    ota_updater_status_t snapshot = { 0 };
    snapshot.state = state;
    strlcpy(snapshot.current_version, esp_app_get_description()->version, sizeof(snapshot.current_version));
    strlcpy(snapshot.available_version, available != NULL ? available : "", sizeof(snapshot.available_version));
    snapshot.progress_percent = progress > 100 ? 100 : progress;
    strlcpy(snapshot.detail, detail != NULL ? detail : "", sizeof(snapshot.detail));
    taskENTER_CRITICAL(&status_lock);
    current_status = snapshot;
    taskEXIT_CRITICAL(&status_lock);
    if (status_callback != NULL) status_callback(&snapshot);
}

#if CONFIG_ILO_OTA_DELIVERY
static void network_event(void *argument, esp_event_base_t base, int32_t event_id, void *event_data)
{
    (void)argument; (void)event_data;
    if (network_events == NULL) return;
    if (base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) xEventGroupSetBits(network_events, NETWORK_READY);
    if (base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) xEventGroupClearBits(network_events, NETWORK_READY);
}

static bool wait_for_trusted_clock(uint32_t timeout_ms)
{
    const time_t earliest_trusted = 1735689600; // 2025-01-01T00:00:00Z
    TickType_t started = xTaskGetTickCount();
    while (time(NULL) < earliest_trusted) {
        if ((xTaskGetTickCount() - started) * portTICK_PERIOD_MS >= timeout_ms) return false;
        vTaskDelay(pdMS_TO_TICKS(250));
    }
    return true;
}

static bool wait_for_network(uint32_t timeout_ms)
{
    if (network_events == NULL) return false;
    EventBits_t bits = xEventGroupWaitBits(network_events, NETWORK_READY, pdFALSE, pdTRUE, pdMS_TO_TICKS(timeout_ms));
    return (bits & NETWORK_READY) != 0;
}

ota_updater_status_t ota_updater_status(void)
{
    taskENTER_CRITICAL(&status_lock);
    ota_updater_status_t snapshot = current_status;
    taskEXIT_CRITICAL(&status_lock);
    return snapshot;
}

static bool exact_object(cJSON *object, const char *const *names, size_t count)
{
    if (!cJSON_IsObject(object)) return false;
    size_t actual = 0;
    cJSON *item = NULL;
    cJSON_ArrayForEach(item, object) {
        ++actual;
        bool known = false;
        for (size_t index = 0; index < count; ++index) {
            if (strcmp(item->string, names[index]) == 0) {
                known = true;
                break;
            }
        }
        if (!known) return false;
    }
    if (actual != count) return false;
    for (size_t index = 0; index < count; ++index) {
        if (cJSON_GetObjectItemCaseSensitive(object, names[index]) == NULL) return false;
    }
    return true;
}

static bool semantic_version(const char *value, int parts[3])
{
    if (value == NULL || strlen(value) >= 32) return false;
    char tail = 0;
    int matched = sscanf(value, "%d.%d.%d%c", &parts[0], &parts[1], &parts[2], &tail);
    return matched == 3 && parts[0] >= 0 && parts[1] >= 0 && parts[2] >= 0;
}

static int compare_versions(const char *left, const char *right)
{
    int a[3] = { 0 }, b[3] = { 0 };
    if (!semantic_version(left, a) || !semantic_version(right, b)) return 0;
    for (size_t index = 0; index < 3; ++index) {
        if (a[index] < b[index]) return -1;
        if (a[index] > b[index]) return 1;
    }
    return 0;
}

static bool lowercase_sha256(const char *value, uint8_t digest[32])
{
    if (value == NULL || strlen(value) != 64) return false;
    for (size_t index = 0; index < 32; ++index) {
        char pair[3] = { value[index * 2], value[index * 2 + 1], 0 };
        if (!((pair[0] >= '0' && pair[0] <= '9') || (pair[0] >= 'a' && pair[0] <= 'f'))
            || !((pair[1] >= '0' && pair[1] <= '9') || (pair[1] >= 'a' && pair[1] <= 'f'))) return false;
        digest[index] = (uint8_t)strtoul(pair, NULL, 16);
    }
    return true;
}

static esp_err_t collect_http_event(esp_http_client_event_t *event)
{
    response_buffer_t *response = event->user_data;
    if (event->event_id == HTTP_EVENT_ON_DATA && event->data_len > 0) {
        if (response == NULL || response->length + (size_t)event->data_len > MANIFEST_MAX_BYTES) {
            if (response != NULL) response->overflow = true;
            return ESP_FAIL;
        }
        memcpy(response->bytes + response->length, event->data, event->data_len);
        response->length += event->data_len;
    }
    return ESP_OK;
}

static bool verify_manifest_signature(const uint8_t *payload, size_t payload_length, const uint8_t *signature, size_t signature_length)
{
#if CONFIG_ILO_OTA_DELIVERY
    uint8_t digest[32];
    if (mbedtls_sha256(payload, payload_length, digest, 0) != 0) return false;
    mbedtls_pk_context key;
    mbedtls_pk_init(&key);
    int result = mbedtls_pk_parse_public_key(
        &key,
        ota_manifest_public_key_start,
        (size_t)(ota_manifest_public_key_end - ota_manifest_public_key_start)
    );
    mbedtls_pk_rsassa_pss_options options = {
        .mgf1_hash_id = MBEDTLS_MD_SHA256,
        .expected_salt_len = 32,
    };
    if (result == 0 && mbedtls_pk_get_bitlen(&key) == 3072) {
        result = mbedtls_pk_verify_ext(
            MBEDTLS_PK_RSASSA_PSS, &options, &key, MBEDTLS_MD_SHA256,
            digest, sizeof(digest), signature, signature_length
        );
    } else {
        result = -1;
    }
    mbedtls_pk_free(&key);
    return result == 0;
#else
    (void)payload; (void)payload_length; (void)signature; (void)signature_length;
    return false;
#endif
}

static bool trusted_key_id(const char *value)
{
#if CONFIG_ILO_OTA_DELIVERY
    if (value == NULL || strlen(value) != 16) return false;
    mbedtls_pk_context key;
    mbedtls_pk_init(&key);
    int result = mbedtls_pk_parse_public_key(
        &key,
        ota_manifest_public_key_start,
        (size_t)(ota_manifest_public_key_end - ota_manifest_public_key_start)
    );
    uint8_t der[512];
    int der_length = result == 0 ? mbedtls_pk_write_pubkey_der(&key, der, sizeof(der)) : -1;
    mbedtls_pk_free(&key);
    if (der_length <= 0) return false;
    uint8_t digest[32];
    if (mbedtls_sha256(der + sizeof(der) - der_length, (size_t)der_length, digest, 0) != 0) return false;
    char expected[17];
    for (size_t index = 0; index < 8; ++index) snprintf(expected + index * 2, 3, "%02x", digest[index]);
    return strcmp(value, expected) == 0;
#else
    (void)value;
    return false;
#endif
}

static bool parse_verified_manifest(const uint8_t *data, size_t length, verified_manifest_t *result)
{
    if (data == NULL || length == 0 || length > MANIFEST_MAX_BYTES || result == NULL) return false;
    cJSON *envelope = cJSON_ParseWithLength((const char *)data, length);
    const char *const envelope_fields[] = { "schema", "algorithm", "keyID", "payload", "signature" };
    if (!exact_object(envelope, envelope_fields, 5)) {
        cJSON_Delete(envelope);
        return false;
    }
    cJSON *schema = cJSON_GetObjectItemCaseSensitive(envelope, "schema");
    cJSON *algorithm = cJSON_GetObjectItemCaseSensitive(envelope, "algorithm");
    cJSON *key_id = cJSON_GetObjectItemCaseSensitive(envelope, "keyID");
    cJSON *payload_item = cJSON_GetObjectItemCaseSensitive(envelope, "payload");
    cJSON *signature_item = cJSON_GetObjectItemCaseSensitive(envelope, "signature");
    if (!cJSON_IsString(schema) || strcmp(schema->valuestring, ENVELOPE_SCHEMA) != 0
        || !cJSON_IsString(algorithm) || strcmp(algorithm->valuestring, SIGNATURE_ALGORITHM) != 0
        || !cJSON_IsString(key_id) || !trusted_key_id(key_id->valuestring)
        || !cJSON_IsString(payload_item) || !cJSON_IsString(signature_item)) {
        cJSON_Delete(envelope);
        return false;
    }
    uint8_t *payload = malloc(PAYLOAD_MAX_BYTES + 1);
    uint8_t signature[SIGNATURE_BYTES];
    size_t payload_length = 0, signature_length = 0;
    bool valid = payload != NULL
        && mbedtls_base64_decode(payload, PAYLOAD_MAX_BYTES, &payload_length,
            (const uint8_t *)payload_item->valuestring, strlen(payload_item->valuestring)) == 0
        && payload_length > 0
        && mbedtls_base64_decode(signature, sizeof(signature), &signature_length,
            (const uint8_t *)signature_item->valuestring, strlen(signature_item->valuestring)) == 0
        && signature_length == SIGNATURE_BYTES
        && verify_manifest_signature(payload, payload_length, signature, signature_length);
    cJSON_Delete(envelope);
    if (!valid) {
        free(payload);
        return false;
    }
    payload[payload_length] = 0;
    cJSON *json = cJSON_ParseWithLength((const char *)payload, payload_length);
    free(payload);
    const char *const payload_fields[] = {
        "schema", "target", "channel", "version", "sequence", "publishedAt",
        "minimumUpdaterVersion", "artifact", "releaseNotes"
    };
    const char *const artifact_fields[] = { "url", "size", "sha256" };
    if (!exact_object(json, payload_fields, 9)) {
        cJSON_Delete(json);
        return false;
    }
    cJSON *payload_schema = cJSON_GetObjectItemCaseSensitive(json, "schema");
    cJSON *target = cJSON_GetObjectItemCaseSensitive(json, "target");
    cJSON *channel = cJSON_GetObjectItemCaseSensitive(json, "channel");
    cJSON *version = cJSON_GetObjectItemCaseSensitive(json, "version");
    cJSON *sequence = cJSON_GetObjectItemCaseSensitive(json, "sequence");
    cJSON *published = cJSON_GetObjectItemCaseSensitive(json, "publishedAt");
    cJSON *minimum = cJSON_GetObjectItemCaseSensitive(json, "minimumUpdaterVersion");
    cJSON *release_notes = cJSON_GetObjectItemCaseSensitive(json, "releaseNotes");
    cJSON *artifact = cJSON_GetObjectItemCaseSensitive(json, "artifact");
    cJSON *url = cJSON_GetObjectItemCaseSensitive(artifact, "url");
    cJSON *size = cJSON_GetObjectItemCaseSensitive(artifact, "size");
    cJSON *sha256 = cJSON_GetObjectItemCaseSensitive(artifact, "sha256");
    int version_parts[3], minimum_parts[3];
    const char *expected_prefix = CONFIG_ILO_OTA_RELEASE_URL_PREFIX;
    bool published_valid = cJSON_IsString(published) && strlen(published->valuestring) == 20
        && published->valuestring[4] == '-' && published->valuestring[7] == '-'
        && published->valuestring[10] == 'T' && published->valuestring[13] == ':'
        && published->valuestring[16] == ':' && published->valuestring[19] == 'Z';
    for (size_t index = 0; published_valid && index < 20; ++index) {
        if (index == 4 || index == 7 || index == 10 || index == 13 || index == 16 || index == 19) continue;
        published_valid = published->valuestring[index] >= '0' && published->valuestring[index] <= '9';
    }
    bool notes_valid = cJSON_IsArray(release_notes)
        && cJSON_GetArraySize(release_notes) >= 1 && cJSON_GetArraySize(release_notes) <= 8;
    cJSON *note = NULL;
    cJSON_ArrayForEach(note, release_notes) {
        size_t note_length = cJSON_IsString(note) ? strlen(note->valuestring) : 0;
        if (note_length < 1 || note_length > 180) notes_valid = false;
        for (size_t index = 0; notes_valid && index < note_length; ++index) {
            if ((unsigned char)note->valuestring[index] < 0x20) notes_valid = false;
        }
    }
    valid = cJSON_IsString(payload_schema) && strcmp(payload_schema->valuestring, PAYLOAD_SCHEMA) == 0
        && cJSON_IsString(target) && strcmp(target->valuestring, BOARD_TARGET) == 0
        && cJSON_IsString(channel) && strcmp(channel->valuestring, "stable") == 0
        && cJSON_IsString(version) && semantic_version(version->valuestring, version_parts)
        && cJSON_IsNumber(sequence) && sequence->valuedouble >= 1 && sequence->valuedouble <= 2147483647
        && sequence->valuedouble == (double)(uint32_t)sequence->valuedouble
        && published_valid && notes_valid
        && cJSON_IsString(minimum) && semantic_version(minimum->valuestring, minimum_parts)
        && compare_versions(esp_app_get_description()->version, minimum->valuestring) >= 0
        && exact_object(artifact, artifact_fields, 3)
        && cJSON_IsString(url) && strncmp(url->valuestring, expected_prefix, strlen(expected_prefix)) == 0
        && strstr(url->valuestring + strlen(expected_prefix), "/") == NULL
        && cJSON_IsNumber(size) && size->valuedouble >= 1 && size->valuedouble <= 0x400000
        && size->valuedouble == (double)(size_t)size->valuedouble
        && cJSON_IsString(sha256) && lowercase_sha256(sha256->valuestring, result->sha256);
    if (valid) {
        char expected_url[256];
        snprintf(expected_url, sizeof(expected_url), "%sILOBoardFirmware-%s.bin", expected_prefix, version->valuestring);
        valid = strcmp(url->valuestring, expected_url) == 0;
    }
    if (valid) {
        strlcpy(result->version, version->valuestring, sizeof(result->version));
        result->sequence = (uint32_t)sequence->valuedouble;
        strlcpy(result->url, url->valuestring, sizeof(result->url));
        result->size = (size_t)size->valuedouble;
    }
    cJSON_Delete(json);
    return valid;
}

static uint32_t installed_sequence(void)
{
    nvs_handle_t handle;
    uint32_t value = 0;
    if (nvs_open(OTA_NAMESPACE, NVS_READONLY, &handle) == ESP_OK) {
        (void)nvs_get_u32(handle, "active_seq", &value);
        nvs_close(handle);
    }
    return value;
}

static bool remember_pending(const verified_manifest_t *manifest)
{
    nvs_handle_t handle;
    if (nvs_open(OTA_NAMESPACE, NVS_READWRITE, &handle) != ESP_OK) return false;
    esp_err_t result = nvs_set_u32(handle, "pending_seq", manifest->sequence);
    if (result == ESP_OK) result = nvs_set_str(handle, "pending_ver", manifest->version);
    if (result == ESP_OK) result = nvs_commit(handle);
    nvs_close(handle);
    if (result != ESP_OK) ESP_LOGE(TAG, "Unable to save pending release sequence");
    return result == ESP_OK;
}

static void reconcile_pending_sequence(void)
{
    nvs_handle_t handle;
    if (nvs_open(OTA_NAMESPACE, NVS_READWRITE, &handle) != ESP_OK) return;
    uint32_t pending = 0;
    char version[32] = { 0 };
    size_t size = sizeof(version);
    if (nvs_get_u32(handle, "pending_seq", &pending) == ESP_OK
        && nvs_get_str(handle, "pending_ver", version, &size) == ESP_OK) {
        const esp_partition_t *running = esp_ota_get_running_partition();
        esp_ota_img_states_t state = ESP_OTA_IMG_UNDEFINED;
        if (strcmp(version, esp_app_get_description()->version) == 0
            && running != NULL && esp_ota_get_state_partition(running, &state) == ESP_OK
            && state == ESP_OTA_IMG_VALID) {
            (void)nvs_set_u32(handle, "active_seq", pending);
            (void)nvs_erase_key(handle, "pending_seq");
            (void)nvs_erase_key(handle, "pending_ver");
            (void)nvs_commit(handle);
        } else if (strcmp(version, esp_app_get_description()->version) != 0) {
            (void)nvs_erase_key(handle, "pending_seq");
            (void)nvs_erase_key(handle, "pending_ver");
            (void)nvs_commit(handle);
        }
    }
    nvs_close(handle);
}

static bool fetch_manifest(verified_manifest_t *manifest)
{
    response_buffer_t response = { .bytes = calloc(1, MANIFEST_MAX_BYTES + 1) };
    if (response.bytes == NULL) return false;
    esp_http_client_config_t config = {
        .url = CONFIG_ILO_OTA_MANIFEST_URL,
        .event_handler = collect_http_event,
        .user_data = &response,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 15000,
        .buffer_size = 4096,
        .disable_auto_redirect = true,
        .user_agent = "ILOBoard/0.2 OTA",
    };
    esp_http_client_handle_t client = esp_http_client_init(&config);
    esp_err_t status = client != NULL ? esp_http_client_perform(client) : ESP_ERR_NO_MEM;
    int http_status = client != NULL ? esp_http_client_get_status_code(client) : 0;
    if (client != NULL) esp_http_client_cleanup(client);
    bool transport_valid = status == ESP_OK && http_status == 200 && !response.overflow;
    bool valid = transport_valid && parse_verified_manifest(response.bytes, response.length, manifest);
    if (!transport_valid) {
        ESP_LOGW(
            TAG,
            "Manifest request failed: transport=%s HTTP=%d bytes=%u overflow=%s",
            esp_err_to_name(status),
            http_status,
            (unsigned)response.length,
            response.overflow ? "yes" : "no"
        );
    } else if (!valid) {
        ESP_LOGW(TAG, "Manifest response was not accepted (%u bytes)", (unsigned)response.length);
    } else {
        ESP_LOGI(
            TAG,
            "Verified signed manifest for %s (sequence %lu); task stack reserve %u bytes",
            manifest->version,
            (unsigned long)manifest->sequence,
            (unsigned)(uxTaskGetStackHighWaterMark(NULL) * sizeof(StackType_t))
        );
    }
    free(response.bytes);
    return valid;
}

static bool download_and_stage(const verified_manifest_t *manifest)
{
    esp_http_client_config_t config = {
        .url = manifest->url,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 20000,
        .buffer_size = DOWNLOAD_BUFFER_BYTES,
        .disable_auto_redirect = true,
        .user_agent = "ILOBoard/0.2 OTA",
    };
    esp_http_client_handle_t client = esp_http_client_init(&config);
    if (client == NULL || esp_http_client_open(client, 0) != ESP_OK) {
        if (client != NULL) esp_http_client_cleanup(client);
        return false;
    }
    int64_t content_length = esp_http_client_fetch_headers(client);
    if (esp_http_client_get_status_code(client) != 200 || content_length != (int64_t)manifest->size) {
        esp_http_client_close(client);
        esp_http_client_cleanup(client);
        return false;
    }
    const esp_partition_t *partition = esp_ota_get_next_update_partition(NULL);
    esp_ota_handle_t handle = 0;
    if (partition == NULL || manifest->size > partition->size
        || esp_ota_begin(partition, manifest->size, &handle) != ESP_OK) {
        esp_http_client_close(client);
        esp_http_client_cleanup(client);
        return false;
    }
    uint8_t *buffer = malloc(DOWNLOAD_BUFFER_BYTES);
    mbedtls_sha256_context sha;
    mbedtls_sha256_init(&sha);
    bool okay = buffer != NULL && mbedtls_sha256_starts(&sha, 0) == 0;
    size_t received = 0;
    while (okay && received < manifest->size) {
        int count = esp_http_client_read(client, (char *)buffer, DOWNLOAD_BUFFER_BYTES);
        if (count <= 0 || received + (size_t)count > manifest->size) {
            okay = false;
            break;
        }
        okay = mbedtls_sha256_update(&sha, buffer, (size_t)count) == 0
            && esp_ota_write(handle, buffer, (size_t)count) == ESP_OK;
        received += (size_t)count;
        uint8_t progress = (uint8_t)((received * 100U) / manifest->size);
        publish_status(OTA_UPDATER_DOWNLOADING, manifest->version, progress, "Downloading signed firmware");
    }
    uint8_t digest[32] = { 0 };
    if (okay) okay = mbedtls_sha256_finish(&sha, digest) == 0;
    mbedtls_sha256_free(&sha);
    free(buffer);
    esp_http_client_close(client);
    esp_http_client_cleanup(client);
    if (!okay || received != manifest->size || memcmp(digest, manifest->sha256, sizeof(digest)) != 0) {
        esp_ota_abort(handle);
        return false;
    }
    publish_status(OTA_UPDATER_VERIFYING, manifest->version, 100, "Verifying image signature");
    if (esp_ota_end(handle) != ESP_OK) return false;
    esp_app_desc_t description = { 0 };
    if (esp_ota_get_partition_description(partition, &description) != ESP_OK
        || strcmp(description.project_name, "ilo_board") != 0
        || strcmp(description.version, manifest->version) != 0
        || !remember_pending(manifest)
        || esp_ota_set_boot_partition(partition) != ESP_OK) return false;
    return true;
}

static void updater_task(void *argument)
{
    (void)argument;
    const esp_partition_t *running = esp_ota_get_running_partition();
    esp_ota_img_states_t initial_state = ESP_OTA_IMG_UNDEFINED;
    if (running != NULL && esp_ota_get_state_partition(running, &initial_state) == ESP_OK
        && initial_state == ESP_OTA_IMG_PENDING_VERIFY) {
        publish_status(OTA_UPDATER_IDLE, NULL, 0, "Completing first-boot health check");
        vTaskDelay(pdMS_TO_TICKS((CONFIG_ILO_OTA_VALIDATION_SECONDS + 2U) * 1000U));
        esp_ota_img_states_t confirmed_state = ESP_OTA_IMG_UNDEFINED;
        if (esp_ota_get_state_partition(running, &confirmed_state) != ESP_OK
            || confirmed_state != ESP_OTA_IMG_VALID) {
            publish_status(OTA_UPDATER_FAILED, NULL, 0, "Current firmware is not confirmed");
            updater_ready = false;
            updater_task_handle = NULL;
            vTaskDelete(NULL);
            return;
        }
    }
    reconcile_pending_sequence();
    if (!wait_for_network(60000)) {
        publish_status(OTA_UPDATER_FAILED, NULL, 0, "Wi-Fi unavailable for update check");
    } else {
        xEventGroupSetBits(commands, COMMAND_CHECK);
    }
    for (;;) {
        EventBits_t bits = xEventGroupWaitBits(
            commands, COMMAND_CHECK | COMMAND_INSTALL, pdTRUE, pdFALSE, portMAX_DELAY
        );
        if ((bits & COMMAND_CHECK) != 0) {
            ESP_LOGI(TAG, "Checking signed firmware manifest");
            publish_status(OTA_UPDATER_CHECKING, NULL, 0, "Checking signed release manifest");
            verified_manifest_t manifest = { 0 };
            if (!wait_for_network(15000)) {
                ESP_LOGW(TAG, "Update check stopped because Wi-Fi is unavailable");
                cached_manifest_valid = false;
                publish_status(OTA_UPDATER_FAILED, NULL, 0, "Wi-Fi unavailable for update check");
                continue;
            }
            if (!wait_for_trusted_clock(30000)) {
                ESP_LOGW(TAG, "Update check stopped because the clock is not synchronized");
                cached_manifest_valid = false;
                publish_status(OTA_UPDATER_FAILED, NULL, 0, "Clock unavailable for secure update check");
                continue;
            }
            if (!fetch_manifest(&manifest)) {
                cached_manifest_valid = false;
                publish_status(OTA_UPDATER_FAILED, NULL, 0, "Update manifest was not verified");
                continue;
            }
            if (manifest.sequence <= installed_sequence()
                || compare_versions(manifest.version, esp_app_get_description()->version) <= 0) {
                cached_manifest_valid = false;
                publish_status(OTA_UPDATER_UP_TO_DATE, NULL, 100, "Firmware is up to date");
                continue;
            }
            cached_manifest = manifest;
            cached_manifest_valid = true;
            ESP_LOGI(TAG, "Signed firmware %s is available", manifest.version);
            publish_status(OTA_UPDATER_AVAILABLE, manifest.version, 0, "Signed update available");
        }
        if ((bits & COMMAND_INSTALL) != 0) {
            if (!cached_manifest_valid) {
                xEventGroupSetBits(commands, COMMAND_CHECK);
                continue;
            }
            verified_manifest_t manifest = cached_manifest;
            cached_manifest_valid = false;
            if (!download_and_stage(&manifest)) {
                publish_status(OTA_UPDATER_FAILED, manifest.version, 0, "Firmware download or verification failed");
                continue;
            }
            publish_status(OTA_UPDATER_REBOOTING, manifest.version, 100, "Update verified; rebooting");
            vTaskDelay(pdMS_TO_TICKS(1200));
            esp_restart();
        }
    }
}
#endif

bool ota_updater_start(ota_updater_status_callback_t callback)
{
    status_callback = callback;
#if !CONFIG_ILO_OTA_DELIVERY
    publish_status(OTA_UPDATER_DISABLED, NULL, 0, "Signed OTA is not enabled in this build");
    return false;
#else
    if (updater_ready && updater_task_handle != NULL) return true;
    bool wifi_handler_registered = false;
    bool ip_handler_registered = false;
    commands = xEventGroupCreate();
    network_events = xEventGroupCreate();
    if (commands != NULL) {
        wifi_handler_registered = esp_event_handler_register(
            WIFI_EVENT, ESP_EVENT_ANY_ID, network_event, NULL
        ) == ESP_OK;
    }
    if (wifi_handler_registered) {
        ip_handler_registered = esp_event_handler_register(
            IP_EVENT, IP_EVENT_STA_GOT_IP, network_event, NULL
        ) == ESP_OK;
    }
    if (commands != NULL && network_events != NULL && wifi_handler_registered && ip_handler_registered) {
        updater_task_handle = xTaskCreateStatic(
            updater_task,
            "ota_updater",
            sizeof(updater_task_stack) / sizeof(updater_task_stack[0]),
            NULL,
            4,
            updater_task_stack,
            &updater_task_storage
        );
    }
    if (updater_task_handle == NULL) {
        if (ip_handler_registered) {
            (void)esp_event_handler_unregister(IP_EVENT, IP_EVENT_STA_GOT_IP, network_event);
        }
        if (wifi_handler_registered) {
            (void)esp_event_handler_unregister(WIFI_EVENT, ESP_EVENT_ANY_ID, network_event);
        }
        if (network_events != NULL) vEventGroupDelete(network_events);
        if (commands != NULL) vEventGroupDelete(commands);
        network_events = NULL;
        commands = NULL;
        updater_ready = false;
        ESP_LOGE(TAG, "Updater worker could not start");
        publish_status(OTA_UPDATER_FAILED, NULL, 0, "Updater task could not start");
        return false;
    }
    updater_ready = true;
    esp_netif_t *station = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
    esp_netif_ip_info_t address = { 0 };
    if (station != NULL && esp_netif_get_ip_info(station, &address) == ESP_OK && address.ip.addr != 0) {
        xEventGroupSetBits(network_events, NETWORK_READY);
    }
    publish_status(OTA_UPDATER_IDLE, NULL, 0, "Waiting for network");
    ESP_LOGI(TAG, "Updater worker ready with %u-byte static stack", (unsigned)sizeof(updater_task_stack));
    return true;
#endif
}

bool ota_updater_request_check(void)
{
#if CONFIG_ILO_OTA_DELIVERY
    if (!updater_ready || updater_task_handle == NULL || commands == NULL) {
        ESP_LOGW(TAG, "Update check rejected because the updater worker is unavailable");
        return false;
    }
    ota_updater_status_t status = ota_updater_status();
    if (status.state == OTA_UPDATER_DOWNLOADING || status.state == OTA_UPDATER_VERIFYING
        || status.state == OTA_UPDATER_REBOOTING) return false;
    xEventGroupSetBits(commands, COMMAND_CHECK);
    ESP_LOGI(TAG, "Firmware update check queued");
    return true;
#else
    return false;
#endif
}

bool ota_updater_request_install(void)
{
#if CONFIG_ILO_OTA_DELIVERY
    if (!updater_ready || updater_task_handle == NULL || commands == NULL || !cached_manifest_valid) return false;
    ota_updater_status_t status = ota_updater_status();
    if (status.state != OTA_UPDATER_AVAILABLE) return false;
    xEventGroupSetBits(commands, COMMAND_INSTALL);
    return true;
#else
    return false;
#endif
}
