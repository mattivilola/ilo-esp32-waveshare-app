#pragma once

#include <stdbool.h>

#include "dashboard_model.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*mac_transport_model_callback_t)(const dashboard_model_t *model);

bool mac_transport_start(mac_transport_model_callback_t callback);

#ifdef __cplusplus
}
#endif

