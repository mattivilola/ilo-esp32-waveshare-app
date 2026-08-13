#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PCF85063_TIME_REGISTER_COUNT 7

bool pcf85063_decode_epoch(
    const uint8_t registers[PCF85063_TIME_REGISTER_COUNT],
    int64_t *epoch_seconds
);
bool pcf85063_encode_epoch(
    int64_t epoch_seconds,
    uint8_t registers[PCF85063_TIME_REGISTER_COUNT]
);

#ifdef __cplusplus
}
#endif
