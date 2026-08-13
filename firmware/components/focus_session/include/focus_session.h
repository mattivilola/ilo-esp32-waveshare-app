#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "focus_session_model.h"

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t focus_session_init(void);
esp_err_t focus_session_start(uint16_t minutes, int64_t now_epoch);
esp_err_t focus_session_pause(int64_t now_epoch);
esp_err_t focus_session_resume(int64_t now_epoch);
esp_err_t focus_session_add_minutes(uint16_t minutes, int64_t now_epoch);
esp_err_t focus_session_end(int64_t now_epoch);
esp_err_t focus_session_cancel(void);
esp_err_t focus_session_snapshot(int64_t now_epoch, focus_session_snapshot_t *snapshot);
esp_err_t focus_session_acknowledge_completion(void);

#ifdef __cplusplus
}
#endif
