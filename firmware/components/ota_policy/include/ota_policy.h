#pragma once

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Validate the dual-slot layout and remember whether this is a pending first boot. */
esp_err_t ota_policy_begin(void);

/**
 * Start the stability window after board and UI initialization have succeeded.
 * A pending image is confirmed only after all health checks pass.
 */
esp_err_t ota_policy_confirm_after_stability(void);

#ifdef __cplusplus
}
#endif
