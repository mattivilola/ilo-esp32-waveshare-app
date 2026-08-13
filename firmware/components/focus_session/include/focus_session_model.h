#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FOCUS_SESSION_MIN_MINUTES 1U
#define FOCUS_SESSION_MAX_MINUTES 720U

typedef enum {
    FOCUS_SESSION_INACTIVE = 0,
    FOCUS_SESSION_RUNNING = 1,
    FOCUS_SESSION_PAUSED = 2,
} focus_session_status_t;

typedef struct {
    focus_session_status_t status;
    uint16_t duration_minutes;
    int64_t started_epoch;
    int64_t deadline_epoch;
    uint32_t paused_remaining_seconds;
    bool completion_pending;
    int64_t completed_epoch;
} focus_session_state_t;

typedef struct {
    focus_session_status_t status;
    uint16_t duration_minutes;
    uint32_t remaining_seconds;
    uint8_t progress_percent;
    bool completion_pending;
    int64_t completed_epoch;
} focus_session_snapshot_t;

void focus_session_model_reset(focus_session_state_t *state);
bool focus_session_model_start(focus_session_state_t *state, uint16_t minutes, int64_t now_epoch);
bool focus_session_model_pause(focus_session_state_t *state, int64_t now_epoch);
bool focus_session_model_resume(focus_session_state_t *state, int64_t now_epoch);
bool focus_session_model_add_minutes(focus_session_state_t *state, uint16_t minutes, int64_t now_epoch);
bool focus_session_model_end(focus_session_state_t *state, int64_t now_epoch);
bool focus_session_model_cancel(focus_session_state_t *state);
bool focus_session_model_snapshot(
    focus_session_state_t *state,
    int64_t now_epoch,
    focus_session_snapshot_t *snapshot
);

#ifdef __cplusplus
}
#endif
