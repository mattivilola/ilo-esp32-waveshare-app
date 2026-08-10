#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DASHBOARD_MAX_TASKS 6
#define DASHBOARD_MAX_NEWS 5

typedef enum {
    DASHBOARD_TASK_ACTIVE,
    DASHBOARD_TASK_WAITING,
    DASHBOARD_TASK_COMPLETED,
    DASHBOARD_TASK_FAILED,
    DASHBOARD_TASK_IDLE,
} dashboard_task_state_t;

typedef enum {
    DASHBOARD_ATTENTION_NONE,
    DASHBOARD_ATTENTION_QUESTION,
    DASHBOARD_ATTENTION_APPROVAL,
} dashboard_attention_t;

typedef struct {
    char id[81];
    char title[81];
    dashboard_task_state_t state;
    dashboard_attention_t attention;
    char summary[181];
} dashboard_task_t;

typedef struct {
    char category[10];
    char headline[71];
    char summary[221];
    char confidence[7];
    char handle[17];
} dashboard_news_story_t;

typedef struct {
    uint64_t revision;
    uint8_t task_count;
    dashboard_task_t tasks[DASHBOARD_MAX_TASKS];
    uint8_t news_count;
    dashboard_news_story_t news[DASHBOARD_MAX_NEWS];
} dashboard_model_t;

dashboard_model_t dashboard_model_demo(void);

#ifdef __cplusplus
}
#endif
