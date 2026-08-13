#include <assert.h>
#include <string.h>

#include "weather_model.h"
#include "weather_visual.h"

int main(void)
{
    assert(WEATHER_FORECAST_DAYS == 4);
    assert(weather_visual_for_code(0) == WEATHER_VISUAL_CLEAR);
    assert(weather_visual_for_code(2) == WEATHER_VISUAL_PARTLY_CLOUDY);
    assert(weather_visual_for_code(45) == WEATHER_VISUAL_FOG);
    assert(weather_visual_for_code(53) == WEATHER_VISUAL_DRIZZLE);
    assert(weather_visual_for_code(63) == WEATHER_VISUAL_RAIN);
    assert(weather_visual_for_code(75) == WEATHER_VISUAL_SNOW);
    assert(weather_visual_for_code(81) == WEATHER_VISUAL_SHOWERS);
    assert(weather_visual_for_code(86) == WEATHER_VISUAL_SNOW);
    assert(weather_visual_for_code(96) == WEATHER_VISUAL_THUNDERSTORM);
    assert(weather_visual_for_code(-1) == WEATHER_VISUAL_MIXED);

    assert(strcmp(weather_condition_for_code(0), "Clear") == 0);
    assert(strcmp(weather_condition_for_code(51), "Drizzle") == 0);
    assert(strcmp(weather_condition_for_code(85), "Snow showers") == 0);
    assert(strcmp(weather_condition_for_code(99), "Thunderstorm") == 0);
    return 0;
}
