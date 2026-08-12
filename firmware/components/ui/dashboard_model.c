#include "dashboard_model.h"

#include <string.h>

dashboard_model_t dashboard_model_demo(void)
{
    dashboard_model_t model = { .revision = 0, .task_count = 3 };
    const dashboard_task_t tasks[] = {
        {
            .id = "board-foundation",
            .title = "Board foundation",
            .state = DASHBOARD_TASK_ACTIVE,
            .attention = DASHBOARD_ATTENTION_NONE,
            .summary = "Display, touch, and network foundations",
        },
        {
            .id = "mac-service",
            .title = "Mac service",
            .state = DASHBOARD_TASK_ACTIVE,
            .attention = DASHBOARD_ATTENTION_NONE,
            .summary = "Waiting for wireless pairing",
        },
        {
            .id = "codex-decisions",
            .title = "Codex decisions",
            .state = DASHBOARD_TASK_WAITING,
            .attention = DASHBOARD_ATTENTION_APPROVAL,
            .summary = "Review stays on Mac - fixed continue only",
        },
    };
    memcpy(model.tasks, tasks, sizeof(tasks));
    return model;
}
