#include <assert.h>
#include <stdint.h>

#include "rtc_time_codec.h"

int main(void)
{
    uint8_t encoded[PCF85063_TIME_REGISTER_COUNT] = { 0 };
    int64_t decoded = 0;

    // 2026-08-13 12:34:56 UTC, Thursday.
    assert(pcf85063_encode_epoch(1786624496LL, encoded));
    const uint8_t expected[] = { 0x56, 0x34, 0x12, 0x13, 0x04, 0x08, 0x26 };
    for (int index = 0; index < PCF85063_TIME_REGISTER_COUNT; ++index) {
        assert(encoded[index] == expected[index]);
    }
    assert(pcf85063_decode_epoch(encoded, &decoded));
    assert(decoded == 1786624496LL);

    const uint8_t leap_day[] = { 0x58, 0x59, 0x23, 0x29, 0x04, 0x02, 0x24 };
    assert(pcf85063_decode_epoch(leap_day, &decoded));
    assert(decoded == 1709251198LL);

    uint8_t oscillator_stopped[] = { 0x80, 0x00, 0x00, 0x01, 0x01, 0x01, 0x26 };
    assert(!pcf85063_decode_epoch(oscillator_stopped, &decoded));

    uint8_t invalid_date[] = { 0x00, 0x00, 0x00, 0x30, 0x05, 0x02, 0x26 };
    assert(!pcf85063_decode_epoch(invalid_date, &decoded));
    assert(!pcf85063_encode_epoch(946684799LL, encoded));
    assert(!pcf85063_encode_epoch(4102444800LL, encoded));
    return 0;
}
