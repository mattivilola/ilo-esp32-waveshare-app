#pragma once

#include <stdbool.h>

#include "weather_model.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*weather_model_callback_t)(const weather_model_t *model);

bool weather_client_start(weather_model_callback_t callback);

#ifdef __cplusplus
}
#endif
