#pragma once

#include <stdbool.h>

#include "weather_model.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*weather_model_callback_t)(const weather_model_t *model);

bool weather_client_start(weather_model_callback_t callback);
bool weather_client_update_location(const char *name, double latitude, double longitude);

#ifdef __cplusplus
}
#endif
