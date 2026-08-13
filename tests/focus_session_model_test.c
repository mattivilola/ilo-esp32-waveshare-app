#include <assert.h>
#include <stdint.h>

#include "focus_session_model.h"

int main(void)
{
    focus_session_state_t state;
    focus_session_snapshot_t snapshot;
    focus_session_model_reset(&state);
    assert(focus_session_model_start(&state, 25, 1000));
    assert(focus_session_model_snapshot(&state, 1001, &snapshot));
    assert(snapshot.status == FOCUS_SESSION_RUNNING);
    assert(snapshot.remaining_seconds == 1499);
    assert(snapshot.progress_percent == 0);

    assert(focus_session_model_pause(&state, 1060));
    assert(focus_session_model_snapshot(&state, 9999, &snapshot));
    assert(snapshot.status == FOCUS_SESSION_PAUSED);
    assert(snapshot.remaining_seconds == 1440);
    assert(focus_session_model_add_minutes(&state, 5, 9999));
    assert(focus_session_model_resume(&state, 2000));
    assert(focus_session_model_snapshot(&state, 2000, &snapshot));
    assert(snapshot.remaining_seconds == 1740);
    assert(snapshot.duration_minutes == 30);

    assert(focus_session_model_snapshot(&state, 3740, &snapshot));
    assert(snapshot.status == FOCUS_SESSION_INACTIVE);
    assert(snapshot.remaining_seconds == 0);
    assert(snapshot.progress_percent == 100);
    assert(snapshot.completion_pending);
    assert(snapshot.completed_epoch == 3740);

    assert(focus_session_model_start(&state, 25, 4000));
    assert(focus_session_model_cancel(&state));
    assert(!state.completion_pending);
    assert(state.status == FOCUS_SESSION_INACTIVE);

    assert(!focus_session_model_start(&state, 0, 5000));
    assert(!focus_session_model_start(&state, 721, 5000));
    return 0;
}
