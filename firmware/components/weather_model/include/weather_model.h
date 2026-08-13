#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WEATHER_FORECAST_DAYS 4

typedef enum {
    WEATHER_STATE_NOT_CONFIGURED,
    WEATHER_STATE_LOADING,
    WEATHER_STATE_LIVE,
    WEATHER_STATE_STALE,
    WEATHER_STATE_ERROR,
} weather_state_t;

typedef struct {
    int weather_code;
    float maximum_c;
    float minimum_c;
} weather_day_t;

typedef struct {
    weather_state_t state;
    char location[41];
    float temperature_c;
    float apparent_c;
    float wind_ms;
    int weather_code;
    int64_t updated_epoch;
    int32_t utc_offset_seconds;
    char timezone_abbreviation[8];
    weather_day_t days[WEATHER_FORECAST_DAYS];
    uint8_t day_count;
} weather_model_t;

#ifdef __cplusplus
}
#endif
