#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    WEATHER_VISUAL_CLEAR,
    WEATHER_VISUAL_PARTLY_CLOUDY,
    WEATHER_VISUAL_FOG,
    WEATHER_VISUAL_DRIZZLE,
    WEATHER_VISUAL_RAIN,
    WEATHER_VISUAL_SNOW,
    WEATHER_VISUAL_SHOWERS,
    WEATHER_VISUAL_THUNDERSTORM,
    WEATHER_VISUAL_MIXED,
} weather_visual_t;

weather_visual_t weather_visual_for_code(int code);
const char *weather_condition_for_code(int code);

#ifdef __cplusplus
}
#endif
