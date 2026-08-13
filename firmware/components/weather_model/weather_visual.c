#include "weather_visual.h"

weather_visual_t weather_visual_for_code(int code)
{
    if (code == 0) return WEATHER_VISUAL_CLEAR;
    if (code >= 1 && code <= 3) return WEATHER_VISUAL_PARTLY_CLOUDY;
    if (code == 45 || code == 48) return WEATHER_VISUAL_FOG;
    if (code >= 51 && code <= 57) return WEATHER_VISUAL_DRIZZLE;
    if (code >= 61 && code <= 67) return WEATHER_VISUAL_RAIN;
    if (code >= 71 && code <= 77) return WEATHER_VISUAL_SNOW;
    if (code >= 80 && code <= 82) return WEATHER_VISUAL_SHOWERS;
    if (code == 85 || code == 86) return WEATHER_VISUAL_SNOW;
    if (code >= 95 && code <= 99) return WEATHER_VISUAL_THUNDERSTORM;
    return WEATHER_VISUAL_MIXED;
}

const char *weather_condition_for_code(int code)
{
    switch (weather_visual_for_code(code)) {
    case WEATHER_VISUAL_CLEAR: return "Clear";
    case WEATHER_VISUAL_PARTLY_CLOUDY: return "Partly cloudy";
    case WEATHER_VISUAL_FOG: return "Fog";
    case WEATHER_VISUAL_DRIZZLE: return "Drizzle";
    case WEATHER_VISUAL_RAIN: return "Rain";
    case WEATHER_VISUAL_SNOW:
        return code == 85 || code == 86 ? "Snow showers" : "Snow";
    case WEATHER_VISUAL_SHOWERS: return "Rain showers";
    case WEATHER_VISUAL_THUNDERSTORM: return "Thunderstorm";
    case WEATHER_VISUAL_MIXED:
    default: return "Mixed conditions";
    }
}
