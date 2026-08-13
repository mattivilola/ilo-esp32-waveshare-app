#include "focus_session_model.h"

#include <limits.h>
#include <stddef.h>

static uint32_t remaining_seconds(const focus_session_state_t *state, int64_t now_epoch)
{
    if (state->status == FOCUS_SESSION_PAUSED) return state->paused_remaining_seconds;
    if (state->status != FOCUS_SESSION_RUNNING || now_epoch >= state->deadline_epoch) return 0;
    int64_t remaining = state->deadline_epoch - now_epoch;
    return remaining > UINT32_MAX ? UINT32_MAX : (uint32_t)remaining;
}

static uint8_t progress_percent(const focus_session_state_t *state, uint32_t remaining)
{
    uint32_t total = (uint32_t)state->duration_minutes * 60U;
    if (total == 0 || remaining == 0) return remaining == 0 ? 100 : 0;
    uint32_t elapsed = remaining >= total ? 0 : total - remaining;
    uint32_t percent = (elapsed * 100U) / total;
    return percent > 100U ? 100U : (uint8_t)percent;
}

void focus_session_model_reset(focus_session_state_t *state)
{
    if (state == NULL) return;
    *state = (focus_session_state_t){ 0 };
}

bool focus_session_model_start(focus_session_state_t *state, uint16_t minutes, int64_t now_epoch)
{
    if (state == NULL || minutes < FOCUS_SESSION_MIN_MINUTES
        || minutes > FOCUS_SESSION_MAX_MINUTES || now_epoch <= 0) return false;
    int64_t seconds = (int64_t)minutes * 60LL;
    if (now_epoch > INT64_MAX - seconds) return false;
    *state = (focus_session_state_t){
        .status = FOCUS_SESSION_RUNNING,
        .duration_minutes = minutes,
        .started_epoch = now_epoch,
        .deadline_epoch = now_epoch + seconds,
    };
    return true;
}

bool focus_session_model_pause(focus_session_state_t *state, int64_t now_epoch)
{
    if (state == NULL || state->status != FOCUS_SESSION_RUNNING || now_epoch <= 0) return false;
    uint32_t remaining = remaining_seconds(state, now_epoch);
    if (remaining == 0) return focus_session_model_end(state, now_epoch);
    state->status = FOCUS_SESSION_PAUSED;
    state->paused_remaining_seconds = remaining;
    state->deadline_epoch = 0;
    return true;
}

bool focus_session_model_resume(focus_session_state_t *state, int64_t now_epoch)
{
    if (state == NULL || state->status != FOCUS_SESSION_PAUSED
        || state->paused_remaining_seconds == 0 || now_epoch <= 0
        || now_epoch > INT64_MAX - state->paused_remaining_seconds) return false;
    state->status = FOCUS_SESSION_RUNNING;
    state->deadline_epoch = now_epoch + state->paused_remaining_seconds;
    state->paused_remaining_seconds = 0;
    return true;
}

bool focus_session_model_add_minutes(focus_session_state_t *state, uint16_t minutes, int64_t now_epoch)
{
    if (state == NULL || state->status == FOCUS_SESSION_INACTIVE || minutes == 0
        || now_epoch <= 0) return false;
    uint32_t added = (uint32_t)minutes * 60U;
    uint32_t current = remaining_seconds(state, now_epoch);
    uint32_t maximum = FOCUS_SESSION_MAX_MINUTES * 60U;
    if (current >= maximum || added > maximum - current) return false;
    if (state->duration_minutes > FOCUS_SESSION_MAX_MINUTES - minutes) return false;
    state->duration_minutes += minutes;
    if (state->status == FOCUS_SESSION_PAUSED) {
        state->paused_remaining_seconds = current + added;
    } else {
        if (state->deadline_epoch > INT64_MAX - added) return false;
        state->deadline_epoch += added;
    }
    return true;
}

bool focus_session_model_end(focus_session_state_t *state, int64_t now_epoch)
{
    if (state == NULL || state->status == FOCUS_SESSION_INACTIVE || now_epoch <= 0) return false;
    state->status = FOCUS_SESSION_INACTIVE;
    state->deadline_epoch = 0;
    state->paused_remaining_seconds = 0;
    state->completion_pending = true;
    state->completed_epoch = now_epoch;
    return true;
}

bool focus_session_model_cancel(focus_session_state_t *state)
{
    if (state == NULL || state->status == FOCUS_SESSION_INACTIVE) return false;
    focus_session_model_reset(state);
    return true;
}

bool focus_session_model_snapshot(
    focus_session_state_t *state,
    int64_t now_epoch,
    focus_session_snapshot_t *snapshot
)
{
    if (state == NULL || snapshot == NULL || now_epoch <= 0) return false;
    if (state->status == FOCUS_SESSION_RUNNING && remaining_seconds(state, now_epoch) == 0) {
        (void)focus_session_model_end(state, now_epoch);
    }
    uint32_t remaining = remaining_seconds(state, now_epoch);
    *snapshot = (focus_session_snapshot_t){
        .status = state->status,
        .duration_minutes = state->duration_minutes,
        .remaining_seconds = remaining,
        .progress_percent = progress_percent(state, remaining),
        .completion_pending = state->completion_pending,
        .completed_epoch = state->completed_epoch,
    };
    return true;
}
