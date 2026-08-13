#include "rtc_time_codec.h"

#include <stddef.h>

#define SECONDS_PER_DAY 86400LL
#define UNIX_EPOCH_YEAR 1970
#define RTC_FIRST_YEAR 2000
#define RTC_LAST_YEAR 2099

static bool is_leap_year(int year)
{
    return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}

static int days_in_month(int year, int month)
{
    static const uint8_t days[] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month == 2 && is_leap_year(year)) return 29;
    return days[month - 1];
}

static bool decode_bcd(uint8_t value, int maximum, int *decoded)
{
    int tens = value >> 4;
    int units = value & 0x0F;
    int result = tens * 10 + units;
    if (decoded == NULL || tens > 9 || units > 9 || result > maximum) return false;
    *decoded = result;
    return true;
}

static uint8_t encode_bcd(int value)
{
    return (uint8_t)(((value / 10) << 4) | (value % 10));
}

static int64_t days_before_year(int year)
{
    int64_t days = 0;
    for (int candidate = UNIX_EPOCH_YEAR; candidate < year; ++candidate) {
        days += is_leap_year(candidate) ? 366 : 365;
    }
    return days;
}

static int64_t epoch_from_fields(int year, int month, int day, int hour, int minute, int second)
{
    int64_t days = days_before_year(year);
    for (int candidate = 1; candidate < month; ++candidate) {
        days += days_in_month(year, candidate);
    }
    days += day - 1;
    return days * SECONDS_PER_DAY + hour * 3600LL + minute * 60LL + second;
}

bool pcf85063_decode_epoch(
    const uint8_t registers[PCF85063_TIME_REGISTER_COUNT],
    int64_t *epoch_seconds
)
{
    if (registers == NULL || epoch_seconds == NULL || (registers[0] & 0x80) != 0) return false;
    if ((registers[1] & 0x80) != 0 || (registers[2] & 0xC0) != 0
        || (registers[3] & 0xC0) != 0 || (registers[4] & 0xF8) != 0
        || (registers[5] & 0xE0) != 0) {
        return false;
    }

    int second;
    int minute;
    int hour;
    int day;
    int weekday;
    int month;
    int short_year;
    if (!decode_bcd(registers[0] & 0x7F, 59, &second)
        || !decode_bcd(registers[1], 59, &minute)
        || !decode_bcd(registers[2], 23, &hour)
        || !decode_bcd(registers[3], 31, &day)
        || !decode_bcd(registers[4], 6, &weekday)
        || !decode_bcd(registers[5], 12, &month)
        || !decode_bcd(registers[6], 99, &short_year)) {
        return false;
    }
    (void)weekday;

    int year = RTC_FIRST_YEAR + short_year;
    if (month < 1 || day < 1 || day > days_in_month(year, month)) return false;
    *epoch_seconds = epoch_from_fields(year, month, day, hour, minute, second);
    return true;
}

bool pcf85063_encode_epoch(
    int64_t epoch_seconds,
    uint8_t registers[PCF85063_TIME_REGISTER_COUNT]
)
{
    const int64_t first_epoch = 946684800LL;
    const int64_t last_epoch = 4102444799LL;
    if (registers == NULL || epoch_seconds < first_epoch || epoch_seconds > last_epoch) return false;

    int64_t days = epoch_seconds / SECONDS_PER_DAY;
    int64_t remaining = epoch_seconds % SECONDS_PER_DAY;
    int year = UNIX_EPOCH_YEAR;
    while (year <= RTC_LAST_YEAR) {
        int year_days = is_leap_year(year) ? 366 : 365;
        if (days < year_days) break;
        days -= year_days;
        ++year;
    }
    if (year < RTC_FIRST_YEAR || year > RTC_LAST_YEAR) return false;

    int month = 1;
    while (month <= 12) {
        int month_days = days_in_month(year, month);
        if (days < month_days) break;
        days -= month_days;
        ++month;
    }
    if (month > 12) return false;

    int day = (int)days + 1;
    int hour = (int)(remaining / 3600);
    remaining %= 3600;
    int minute = (int)(remaining / 60);
    int second = (int)(remaining % 60);
    int64_t absolute_days = epoch_seconds / SECONDS_PER_DAY;
    int weekday = (int)((absolute_days + 4) % 7); // 1970-01-01 was Thursday.

    registers[0] = encode_bcd(second);
    registers[1] = encode_bcd(minute);
    registers[2] = encode_bcd(hour);
    registers[3] = encode_bcd(day);
    registers[4] = encode_bcd(weekday);
    registers[5] = encode_bcd(month);
    registers[6] = encode_bcd(year - RTC_FIRST_YEAR);
    return true;
}
