#include "focus_session.h"

#include <stddef.h>

#include "esp_log.h"
#include "nvs.h"

#define FOCUS_NAMESPACE "ilo_focus"

static const char *TAG = "focus_session";
static focus_session_state_t state;
static bool initialized;

static bool valid_loaded_state(const focus_session_state_t *candidate)
{
    if (candidate->status > FOCUS_SESSION_PAUSED
        || candidate->duration_minutes > FOCUS_SESSION_MAX_MINUTES) return false;
    if (candidate->status == FOCUS_SESSION_INACTIVE) {
        return !candidate->completion_pending
            || (candidate->duration_minutes >= FOCUS_SESSION_MIN_MINUTES
                && candidate->duration_minutes <= FOCUS_SESSION_MAX_MINUTES
                && candidate->completed_epoch > 0);
    }
    if (candidate->duration_minutes < FOCUS_SESSION_MIN_MINUTES || candidate->started_epoch <= 0) return false;
    if (candidate->status == FOCUS_SESSION_RUNNING) return candidate->deadline_epoch > candidate->started_epoch;
    return candidate->paused_remaining_seconds > 0
        && candidate->paused_remaining_seconds <= FOCUS_SESSION_MAX_MINUTES * 60U;
}

static esp_err_t save_state(void)
{
    nvs_handle_t handle;
    esp_err_t status = nvs_open(FOCUS_NAMESPACE, NVS_READWRITE, &handle);
    if (status != ESP_OK) return status;
    if (status == ESP_OK) status = nvs_set_u8(handle, "status", (uint8_t)state.status);
    if (status == ESP_OK) status = nvs_set_u16(handle, "duration", state.duration_minutes);
    if (status == ESP_OK) status = nvs_set_i64(handle, "started", state.started_epoch);
    if (status == ESP_OK) status = nvs_set_i64(handle, "deadline", state.deadline_epoch);
    if (status == ESP_OK) status = nvs_set_u32(handle, "remaining", state.paused_remaining_seconds);
    if (status == ESP_OK) status = nvs_set_u8(handle, "notify", state.completion_pending ? 1 : 0);
    if (status == ESP_OK) status = nvs_set_i64(handle, "completed", state.completed_epoch);
    if (status == ESP_OK) status = nvs_commit(handle);
    nvs_close(handle);
    return status;
}

esp_err_t focus_session_init(void)
{
    if (initialized) return ESP_OK;
    focus_session_model_reset(&state);
    nvs_handle_t handle;
    esp_err_t status = nvs_open(FOCUS_NAMESPACE, NVS_READONLY, &handle);
    if (status == ESP_ERR_NVS_NOT_FOUND) {
        initialized = true;
        return ESP_OK;
    }
    if (status != ESP_OK) return status;
    uint8_t raw_status = 0;
    uint8_t notify = 0;
    (void)nvs_get_u8(handle, "status", &raw_status);
    state.status = (focus_session_status_t)raw_status;
    (void)nvs_get_u16(handle, "duration", &state.duration_minutes);
    (void)nvs_get_i64(handle, "started", &state.started_epoch);
    (void)nvs_get_i64(handle, "deadline", &state.deadline_epoch);
    (void)nvs_get_u32(handle, "remaining", &state.paused_remaining_seconds);
    (void)nvs_get_u8(handle, "notify", &notify);
    state.completion_pending = notify == 1;
    (void)nvs_get_i64(handle, "completed", &state.completed_epoch);
    nvs_close(handle);
    if (!valid_loaded_state(&state)) {
        ESP_LOGW(TAG, "Discarding invalid retained focus state");
        focus_session_model_reset(&state);
        status = save_state();
        if (status != ESP_OK) return status;
    }
    initialized = true;
    return ESP_OK;
}

static esp_err_t apply(bool changed)
{
    if (!initialized) return ESP_ERR_INVALID_STATE;
    if (!changed) return ESP_ERR_INVALID_ARG;
    esp_err_t status = save_state();
    if (status != ESP_OK) ESP_LOGE(TAG, "Unable to persist focus state: %s", esp_err_to_name(status));
    return status;
}

esp_err_t focus_session_start(uint16_t minutes, int64_t now_epoch)
{
    return apply(focus_session_model_start(&state, minutes, now_epoch));
}

esp_err_t focus_session_pause(int64_t now_epoch)
{
    return apply(focus_session_model_pause(&state, now_epoch));
}

esp_err_t focus_session_resume(int64_t now_epoch)
{
    return apply(focus_session_model_resume(&state, now_epoch));
}

esp_err_t focus_session_add_minutes(uint16_t minutes, int64_t now_epoch)
{
    return apply(focus_session_model_add_minutes(&state, minutes, now_epoch));
}

esp_err_t focus_session_end(int64_t now_epoch)
{
    return apply(focus_session_model_end(&state, now_epoch));
}

esp_err_t focus_session_cancel(void)
{
    return apply(focus_session_model_cancel(&state));
}

esp_err_t focus_session_snapshot(int64_t now_epoch, focus_session_snapshot_t *snapshot)
{
    if (!initialized || snapshot == NULL) return ESP_ERR_INVALID_STATE;
    focus_session_status_t previous_status = state.status;
    if (!focus_session_model_snapshot(&state, now_epoch, snapshot)) return ESP_ERR_INVALID_ARG;
    if (previous_status != state.status) return save_state();
    return ESP_OK;
}

esp_err_t focus_session_acknowledge_completion(void)
{
    if (!initialized) return ESP_ERR_INVALID_STATE;
    state.completion_pending = false;
    return save_state();
}
