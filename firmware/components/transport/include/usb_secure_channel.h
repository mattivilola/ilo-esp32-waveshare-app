#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "cJSON.h"
#include "esp_err.h"

typedef struct {
    uint8_t key[32];
    uint64_t send_sequence;
    uint64_t receive_sequence;
    char *line;
    size_t line_length;
    bool line_complete;
    uint8_t raw[1024];
    size_t raw_offset;
    size_t raw_count;
    bool authenticated;
    bool pending_data;
} usb_secure_channel_t;

esp_err_t usb_secure_channel_initialize(void);
bool usb_secure_channel_accept(
    usb_secure_channel_t *channel,
    const char *board_id,
    const uint8_t secret[32]
);
bool usb_secure_channel_send_json(usb_secure_channel_t *channel, cJSON *json);
int usb_secure_channel_wait_data(usb_secure_channel_t *channel, uint32_t timeout_ms);
cJSON *usb_secure_channel_read_json(usb_secure_channel_t *channel);
void usb_secure_channel_close(usb_secure_channel_t *channel);
