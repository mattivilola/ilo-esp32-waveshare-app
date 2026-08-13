#pragma once

#include <stdbool.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Validate the dual-slot layout and remember whether this is a pending first boot. */
esp_err_t ota_policy_begin(void);

/** Return whether the running image still requires first-boot confirmation. */
bool ota_policy_confirmation_required(void);

/** Confirm or roll back the pending image after the caller-owned stability window. */
esp_err_t ota_policy_confirm_pending_image(void);

#ifdef __cplusplus
}
#endif
