#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    OTA_UPDATER_DISABLED,
    OTA_UPDATER_IDLE,
    OTA_UPDATER_CHECKING,
    OTA_UPDATER_UP_TO_DATE,
    OTA_UPDATER_AVAILABLE,
    OTA_UPDATER_DOWNLOADING,
    OTA_UPDATER_VERIFYING,
    OTA_UPDATER_REBOOTING,
    OTA_UPDATER_FAILED,
} ota_updater_state_t;

typedef struct {
    ota_updater_state_t state;
    char current_version[32];
    char available_version[32];
    uint8_t progress_percent;
    char detail[96];
} ota_updater_status_t;

typedef void (*ota_updater_status_callback_t)(const ota_updater_status_t *status);

bool ota_updater_start(ota_updater_status_callback_t callback);
bool ota_updater_request_check(void);
bool ota_updater_request_install(void);
ota_updater_status_t ota_updater_status(void);

#ifdef __cplusplus
}
#endif
