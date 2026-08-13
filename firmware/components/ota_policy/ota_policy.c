#include "ota_policy.h"

#include <stdbool.h>
#include <stddef.h>

#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_partition.h"

static const char *TAG = "ota_policy";
static const esp_partition_t *boot_partition;
static bool pending_validation;
static bool policy_initialized;

static esp_err_t validate_layout(void)
{
    const esp_partition_t *running = esp_ota_get_running_partition();
    const esp_partition_t *next = esp_ota_get_next_update_partition(NULL);
    if (esp_ota_get_app_partition_count() != 2 || running == NULL || next == NULL || running == next) {
        ESP_LOGE(TAG, "OTA requires exactly two distinct application slots");
        return ESP_ERR_INVALID_STATE;
    }
    bool running_is_ota = running->subtype == ESP_PARTITION_SUBTYPE_APP_OTA_0
        || running->subtype == ESP_PARTITION_SUBTYPE_APP_OTA_1;
    bool next_is_ota = next->subtype == ESP_PARTITION_SUBTYPE_APP_OTA_0
        || next->subtype == ESP_PARTITION_SUBTYPE_APP_OTA_1;
    if (!running_is_ota || !next_is_ota || running->size != next->size) {
        ESP_LOGE(TAG, "OTA slots must be equal-sized ota_0/ota_1 partitions");
        return ESP_ERR_INVALID_SIZE;
    }
    boot_partition = running;
    ESP_LOGI(
        TAG,
        "Running %s at 0x%08lx; inactive slot %s at 0x%08lx; slot size %lu bytes",
        running->label,
        (unsigned long)running->address,
        next->label,
        (unsigned long)next->address,
        (unsigned long)running->size
    );
    return ESP_OK;
}

static void reject_pending_image(const char *reason)
{
    ESP_LOGE(TAG, "OTA validation failed: %s", reason);
    if (esp_ota_check_rollback_is_possible()) {
        esp_err_t status = esp_ota_mark_app_invalid_rollback_and_reboot();
        ESP_LOGE(TAG, "Rollback request unexpectedly returned: %s", esp_err_to_name(status));
    } else {
        ESP_LOGE(TAG, "No valid rollback image exists; leaving image unconfirmed for USB recovery");
    }
}

bool ota_policy_confirmation_required(void)
{
    return policy_initialized && pending_validation;
}

esp_err_t ota_policy_confirm_pending_image(void)
{
    if (!policy_initialized || !pending_validation) return ESP_ERR_INVALID_STATE;
    if (esp_ota_get_running_partition() != boot_partition) {
        reject_pending_image("running partition changed during validation");
        return ESP_ERR_INVALID_STATE;
    }
    size_t free_internal = heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    esp_ota_img_states_t state = ESP_OTA_IMG_UNDEFINED;
    if (esp_ota_get_state_partition(boot_partition, &state) != ESP_OK || state != ESP_OTA_IMG_PENDING_VERIFY) {
        reject_pending_image("running image is no longer pending verification");
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t status = esp_ota_mark_app_valid_cancel_rollback();
    if (status != ESP_OK) {
        reject_pending_image("could not persist the valid image state");
        return status;
    }
    pending_validation = false;
    ESP_LOGI(
        TAG,
        "OTA image confirmed after %d stable seconds; free internal heap %lu bytes",
        CONFIG_ILO_OTA_VALIDATION_SECONDS,
        (unsigned long)free_internal
    );
    return ESP_OK;
}

esp_err_t ota_policy_begin(void)
{
    if (policy_initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t status = validate_layout();
    if (status != ESP_OK) {
        return status;
    }

    esp_ota_img_states_t state = ESP_OTA_IMG_UNDEFINED;
    status = esp_ota_get_state_partition(boot_partition, &state);
    if (status == ESP_OK) {
        pending_validation = state == ESP_OTA_IMG_PENDING_VERIFY;
        ESP_LOGI(TAG, "Running OTA image state: %d%s", state, pending_validation ? " (validation required)" : "");
    } else if (status == ESP_ERR_NOT_FOUND) {
        pending_validation = false;
        ESP_LOGI(TAG, "Running image has no OTA state yet (normal USB development boot)");
    } else {
        ESP_LOGE(TAG, "Cannot read running OTA state: %s", esp_err_to_name(status));
        return status;
    }
    policy_initialized = true;
    return ESP_OK;
}
