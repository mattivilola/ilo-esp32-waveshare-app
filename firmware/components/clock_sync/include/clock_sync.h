#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

bool clock_sync_start(void);
bool clock_sync_wait(uint32_t timeout_ms);

#ifdef __cplusplus
}
#endif
