#include "usb_secure_channel.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "driver/usb_serial_jtag.h"
#include "driver/usb_serial_jtag_vfs.h"
#include "esp_random.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/base64.h"
#include "mbedtls/chachapoly.h"
#include "mbedtls/hkdf.h"
#include "mbedtls/md.h"

#define USB_PREFIX "~ILOUSB1"
#define USB_FRAME_MAX 65536
#define USB_LINE_MAX 90000
#define USB_NONCE_SIZE 32
#define USB_TAG_SIZE 16
#define USB_AEAD_NONCE_SIZE 12
#define USB_KEY_SIZE 32
#define USB_HANDSHAKE_TIMEOUT_MS 5000

static bool write_line(const char *line)
{
    if (line == NULL) return false;
    size_t line_size = strlen(line);
    if (line_size > USB_LINE_MAX) return false;
    uint8_t *wire = malloc(line_size + 1);
    if (wire == NULL) return false;
    memcpy(wire, line, line_size);
    wire[line_size] = '\n';
    int written = usb_serial_jtag_write_bytes(wire, line_size + 1, portMAX_DELAY);
    free(wire);
    return written == (int)(line_size + 1);
}

static bool bytes_to_hex(const uint8_t *bytes, size_t size, char *hex, size_t capacity)
{
    if (bytes == NULL || hex == NULL || capacity < size * 2 + 1) return false;
    for (size_t index = 0; index < size; ++index) {
        snprintf(&hex[index * 2], 3, "%02x", bytes[index]);
    }
    hex[size * 2] = 0;
    return true;
}

static int hex_value(char value)
{
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    if (value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}

static bool hex_to_bytes(const char *hex, uint8_t *bytes, size_t size)
{
    if (hex == NULL || bytes == NULL || strlen(hex) != size * 2) return false;
    for (size_t index = 0; index < size; ++index) {
        int high = hex_value(hex[index * 2]);
        int low = hex_value(hex[index * 2 + 1]);
        if (high < 0 || low < 0) return false;
        bytes[index] = (uint8_t)((high << 4) | low);
    }
    return true;
}

static bool constant_time_equal(const uint8_t *left, const uint8_t *right, size_t size)
{
    uint8_t difference = 0;
    for (size_t index = 0; index < size; ++index) difference |= left[index] ^ right[index];
    return difference == 0;
}

static bool authentication_code(
    const char *label,
    const uint8_t secret[USB_KEY_SIZE],
    const uint8_t client_nonce[USB_NONCE_SIZE],
    const uint8_t board_nonce[USB_NONCE_SIZE],
    const char *board_id,
    uint8_t output[USB_KEY_SIZE]
)
{
    const mbedtls_md_info_t *sha256 = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (sha256 == NULL || label == NULL || board_id == NULL) return false;
    char label_text[40];
    int label_size = snprintf(label_text, sizeof(label_text), "ILOUSB1 %s", label);
    size_t board_id_size = strlen(board_id);
    size_t payload_size = (size_t)label_size + USB_NONCE_SIZE * 2 + board_id_size;
    if (label_size <= 0 || (size_t)label_size >= sizeof(label_text) || board_id_size == 0 || board_id_size > 80) {
        return false;
    }
    uint8_t *payload = malloc(payload_size);
    if (payload == NULL) return false;
    size_t offset = 0;
    memcpy(payload + offset, label_text, (size_t)label_size);
    offset += (size_t)label_size;
    memcpy(payload + offset, client_nonce, USB_NONCE_SIZE);
    offset += USB_NONCE_SIZE;
    memcpy(payload + offset, board_nonce, USB_NONCE_SIZE);
    offset += USB_NONCE_SIZE;
    memcpy(payload + offset, board_id, board_id_size);
    int status = mbedtls_md_hmac(sha256, secret, USB_KEY_SIZE, payload, payload_size, output);
    free(payload);
    return status == 0;
}

static bool derive_key(
    const uint8_t secret[USB_KEY_SIZE],
    const uint8_t client_nonce[USB_NONCE_SIZE],
    const uint8_t board_nonce[USB_NONCE_SIZE],
    uint8_t output[USB_KEY_SIZE]
)
{
    const mbedtls_md_info_t *sha256 = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    uint8_t salt[USB_NONCE_SIZE * 2];
    memcpy(salt, client_nonce, USB_NONCE_SIZE);
    memcpy(salt + USB_NONCE_SIZE, board_nonce, USB_NONCE_SIZE);
    static const uint8_t info[] = "ILO Board USB v1";
    return sha256 != NULL && mbedtls_hkdf(
        sha256,
        salt,
        sizeof(salt),
        secret,
        USB_KEY_SIZE,
        info,
        sizeof(info) - 1,
        output,
        USB_KEY_SIZE
    ) == 0;
}

static int next_byte(usb_secure_channel_t *channel, uint8_t *value, uint32_t timeout_ms)
{
    if (channel->raw_offset >= channel->raw_count) {
        int count = usb_serial_jtag_read_bytes(
            channel->raw,
            sizeof(channel->raw),
            pdMS_TO_TICKS(timeout_ms)
        );
        if (count <= 0) return count;
        channel->raw_offset = 0;
        channel->raw_count = (size_t)count;
    }
    *value = channel->raw[channel->raw_offset++];
    return 1;
}

static bool read_line(usb_secure_channel_t *channel, uint32_t timeout_ms)
{
    TickType_t started = xTaskGetTickCount();
    if (channel->line_complete) {
        channel->line_length = 0;
        channel->line_complete = false;
    }
    for (;;) {
        uint32_t remaining = timeout_ms;
        if (timeout_ms != UINT32_MAX) {
            uint32_t elapsed = pdTICKS_TO_MS(xTaskGetTickCount() - started);
            if (elapsed >= timeout_ms) return false;
            remaining = timeout_ms - elapsed;
            if (remaining > 100) remaining = 100;
        } else {
            remaining = 100;
        }
        uint8_t byte = 0;
        int result = next_byte(channel, &byte, remaining);
        if (result < 0) return false;
        if (result == 0) continue;
        if (byte == '\n') {
            if (channel->line_length > 0 && channel->line[channel->line_length - 1] == '\r') {
                --channel->line_length;
            }
            channel->line[channel->line_length] = 0;
            channel->line_complete = true;
            return true;
        }
        if (channel->line_length >= USB_LINE_MAX) {
            channel->line_length = 0;
            return false;
        }
        channel->line[channel->line_length++] = (char)byte;
    }
}

static void make_nonce(char direction, uint64_t sequence, uint8_t nonce[USB_AEAD_NONCE_SIZE])
{
    const uint8_t mac_prefix[4] = {'M', 'A', 'C', 0};
    const uint8_t board_prefix[4] = {'B', 'R', 'D', 0};
    memcpy(nonce, direction == 'M' ? mac_prefix : board_prefix, 4);
    for (size_t index = 0; index < 8; ++index) {
        nonce[4 + index] = (uint8_t)(sequence >> ((7 - index) * 8));
    }
}

static bool make_aad(char direction, uint64_t sequence, char *aad, size_t capacity, size_t *size)
{
    int written = snprintf(aad, capacity, "ILOUSB1|%c|%llu", direction, (unsigned long long)sequence);
    if (written <= 0 || (size_t)written >= capacity) return false;
    *size = (size_t)written;
    return true;
}

esp_err_t usb_secure_channel_initialize(void)
{
    usb_serial_jtag_driver_config_t config = {
        .tx_buffer_size = 16384,
        .rx_buffer_size = 4096,
    };
    esp_err_t status = usb_serial_jtag_driver_install(&config);
    if (status != ESP_OK && status != ESP_ERR_INVALID_STATE) return status;
    usb_serial_jtag_vfs_use_driver();
    usb_serial_jtag_vfs_set_rx_line_endings(ESP_LINE_ENDINGS_LF);
    usb_serial_jtag_vfs_set_tx_line_endings(ESP_LINE_ENDINGS_LF);
    return ESP_OK;
}

bool usb_secure_channel_accept(
    usb_secure_channel_t *channel,
    const char *board_id,
    const uint8_t secret[USB_KEY_SIZE]
)
{
    if (channel == NULL || board_id == NULL || secret == NULL) return false;
    memset(channel, 0, sizeof(*channel));
    channel->line = malloc(USB_LINE_MAX + 1);
    if (channel->line == NULL) return false;

    uint8_t client_nonce[USB_NONCE_SIZE];
    char client_nonce_hex[USB_NONCE_SIZE * 2 + 1];
    for (;;) {
        if (!read_line(channel, UINT32_MAX)) goto fail;
        char extra[2];
        if (sscanf(channel->line, USB_PREFIX " HELLO %64s %1s", client_nonce_hex, extra) == 1
            && hex_to_bytes(client_nonce_hex, client_nonce, sizeof(client_nonce))) {
            break;
        }
    }

    uint8_t board_nonce[USB_NONCE_SIZE];
    uint8_t challenge_code[USB_KEY_SIZE];
    char board_nonce_hex[USB_NONCE_SIZE * 2 + 1];
    char challenge_hex[USB_KEY_SIZE * 2 + 1];
    esp_fill_random(board_nonce, sizeof(board_nonce));
    if (!authentication_code("challenge", secret, client_nonce, board_nonce, board_id, challenge_code)
        || !bytes_to_hex(board_nonce, sizeof(board_nonce), board_nonce_hex, sizeof(board_nonce_hex))
        || !bytes_to_hex(challenge_code, sizeof(challenge_code), challenge_hex, sizeof(challenge_hex))) {
        goto fail;
    }
    char challenge_line[256];
    snprintf(
        challenge_line,
        sizeof(challenge_line),
        USB_PREFIX " CHALLENGE %s %s %s",
        board_id,
        board_nonce_hex,
        challenge_hex
    );
    bool sent = write_line(challenge_line);
    if (!sent) goto fail;

    TickType_t auth_started = xTaskGetTickCount();
    for (;;) {
        uint32_t elapsed = pdTICKS_TO_MS(xTaskGetTickCount() - auth_started);
        if (elapsed >= USB_HANDSHAKE_TIMEOUT_MS
            || !read_line(channel, USB_HANDSHAKE_TIMEOUT_MS - elapsed)) {
            goto fail;
        }
        // The Mac repeats the same HELLO while native USB is rebooting. A copy
        // can already be queued when this challenge reaches it; ignore that
        // duplicate instead of interpreting it as a failed AUTH.
        char duplicate_nonce_hex[USB_NONCE_SIZE * 2 + 1];
        char duplicate_extra[2];
        if (sscanf(
                channel->line,
                USB_PREFIX " HELLO %64s %1s",
                duplicate_nonce_hex,
                duplicate_extra
            ) == 1) {
            if (strcmp(duplicate_nonce_hex, client_nonce_hex) == 0
                && !write_line(challenge_line)) goto fail;
            continue;
        }
        break;
    }
    char received_auth_hex[USB_KEY_SIZE * 2 + 1];
    char extra[2];
    uint8_t received_auth[USB_KEY_SIZE];
    uint8_t expected_auth[USB_KEY_SIZE];
    if (sscanf(channel->line, USB_PREFIX " AUTH %64s %1s", received_auth_hex, extra) != 1
        || !hex_to_bytes(received_auth_hex, received_auth, sizeof(received_auth))
        || !authentication_code("auth", secret, client_nonce, board_nonce, board_id, expected_auth)
        || !constant_time_equal(received_auth, expected_auth, sizeof(received_auth))
        || !derive_key(secret, client_nonce, board_nonce, channel->key)
        || !write_line(USB_PREFIX " READY")) {
        goto fail;
    }
    channel->authenticated = true;
    return true;

fail:
    usb_secure_channel_close(channel);
    return false;
}

bool usb_secure_channel_send_json(usb_secure_channel_t *channel, cJSON *json)
{
    if (channel == NULL || !channel->authenticated || json == NULL) return false;
    char *payload = cJSON_PrintUnformatted(json);
    if (payload == NULL) return false;
    size_t payload_size = strlen(payload);
    if (payload_size == 0 || payload_size > USB_FRAME_MAX) {
        free(payload);
        return false;
    }
    size_t plaintext_size = payload_size + 4;
    uint8_t *plaintext = malloc(plaintext_size);
    if (plaintext == NULL) {
        free(payload);
        return false;
    }
    plaintext[0] = (uint8_t)(payload_size >> 24);
    plaintext[1] = (uint8_t)(payload_size >> 16);
    plaintext[2] = (uint8_t)(payload_size >> 8);
    plaintext[3] = (uint8_t)payload_size;
    memcpy(plaintext + 4, payload, payload_size);
    free(payload);

    uint64_t sequence = ++channel->send_sequence;
    uint8_t nonce[USB_AEAD_NONCE_SIZE];
    char aad[40];
    size_t aad_size = 0;
    make_nonce('B', sequence, nonce);
    if (!make_aad('B', sequence, aad, sizeof(aad), &aad_size)) {
        free(plaintext);
        return false;
    }
    uint8_t *combined = malloc(USB_AEAD_NONCE_SIZE + plaintext_size + USB_TAG_SIZE);
    if (combined == NULL) {
        free(plaintext);
        return false;
    }
    memcpy(combined, nonce, sizeof(nonce));
    mbedtls_chachapoly_context crypto;
    mbedtls_chachapoly_init(&crypto);
    int status = mbedtls_chachapoly_setkey(&crypto, channel->key);
    if (status == 0) {
        status = mbedtls_chachapoly_encrypt_and_tag(
            &crypto,
            plaintext_size,
            nonce,
            (const uint8_t *)aad,
            aad_size,
            plaintext,
            combined + USB_AEAD_NONCE_SIZE,
            combined + USB_AEAD_NONCE_SIZE + plaintext_size
        );
    }
    mbedtls_chachapoly_free(&crypto);
    free(plaintext);
    if (status != 0) {
        free(combined);
        return false;
    }

    size_t combined_size = USB_AEAD_NONCE_SIZE + plaintext_size + USB_TAG_SIZE;
    size_t encoded_capacity = ((combined_size + 2) / 3) * 4 + 1;
    char *encoded = malloc(encoded_capacity);
    size_t encoded_size = 0;
    if (encoded == NULL || mbedtls_base64_encode(
            (uint8_t *)encoded,
            encoded_capacity,
            &encoded_size,
            combined,
            combined_size
        ) != 0) {
        free(combined);
        free(encoded);
        return false;
    }
    free(combined);
    encoded[encoded_size] = 0;
    size_t line_capacity = encoded_size + 64;
    char *line = malloc(line_capacity);
    bool ok = line != NULL
        && snprintf(
            line,
            line_capacity,
            USB_PREFIX " DATA B %llu %s",
            (unsigned long long)sequence,
            encoded
        ) > 0
        && write_line(line);
    free(encoded);
    free(line);
    return ok;
}

int usb_secure_channel_wait_data(usb_secure_channel_t *channel, uint32_t timeout_ms)
{
    if (channel == NULL || !channel->authenticated) return -1;
    if (channel->pending_data) return 1;
    TickType_t started = xTaskGetTickCount();
    for (;;) {
        uint32_t elapsed = pdTICKS_TO_MS(xTaskGetTickCount() - started);
        if (elapsed >= timeout_ms) return 0;
        if (!read_line(channel, timeout_ms - elapsed)) return 0;
        if (strncmp(channel->line, USB_PREFIX " DATA M ", strlen(USB_PREFIX " DATA M ")) == 0) {
            channel->pending_data = true;
            return 1;
        }
    }
}

cJSON *usb_secure_channel_read_json(usb_secure_channel_t *channel)
{
    if (channel == NULL || !channel->authenticated || !channel->pending_data) return NULL;
    channel->pending_data = false;
    char *save = NULL;
    char *prefix = strtok_r(channel->line, " ", &save);
    char *data_token = strtok_r(NULL, " ", &save);
    char *direction = strtok_r(NULL, " ", &save);
    char *sequence_text = strtok_r(NULL, " ", &save);
    char *encoded = strtok_r(NULL, " ", &save);
    char *extra = strtok_r(NULL, " ", &save);
    if (prefix == NULL || strcmp(prefix, USB_PREFIX) != 0
        || data_token == NULL || strcmp(data_token, "DATA") != 0
        || direction == NULL || strcmp(direction, "M") != 0
        || sequence_text == NULL || encoded == NULL || extra != NULL) {
        return NULL;
    }
    char *end = NULL;
    unsigned long long parsed_sequence = strtoull(sequence_text, &end, 10);
    uint64_t sequence = (uint64_t)parsed_sequence;
    if (end == NULL || *end != 0 || sequence != channel->receive_sequence + 1) return NULL;

    size_t encoded_size = strlen(encoded);
    size_t combined_capacity = (encoded_size / 4) * 3 + 3;
    uint8_t *combined = malloc(combined_capacity);
    size_t combined_size = 0;
    if (combined == NULL || mbedtls_base64_decode(
            combined,
            combined_capacity,
            &combined_size,
            (const uint8_t *)encoded,
            encoded_size
        ) != 0 || combined_size < USB_AEAD_NONCE_SIZE + USB_TAG_SIZE + 4) {
        free(combined);
        return NULL;
    }
    uint8_t expected_nonce[USB_AEAD_NONCE_SIZE];
    make_nonce('M', sequence, expected_nonce);
    if (!constant_time_equal(combined, expected_nonce, sizeof(expected_nonce))) {
        free(combined);
        return NULL;
    }
    size_t plaintext_size = combined_size - USB_AEAD_NONCE_SIZE - USB_TAG_SIZE;
    if (plaintext_size > USB_FRAME_MAX + 4) {
        free(combined);
        return NULL;
    }
    uint8_t *plaintext = malloc(plaintext_size);
    char aad[40];
    size_t aad_size = 0;
    if (plaintext == NULL || !make_aad('M', sequence, aad, sizeof(aad), &aad_size)) {
        free(combined);
        free(plaintext);
        return NULL;
    }
    mbedtls_chachapoly_context crypto;
    mbedtls_chachapoly_init(&crypto);
    int status = mbedtls_chachapoly_setkey(&crypto, channel->key);
    if (status == 0) {
        status = mbedtls_chachapoly_auth_decrypt(
            &crypto,
            plaintext_size,
            expected_nonce,
            (const uint8_t *)aad,
            aad_size,
            combined + USB_AEAD_NONCE_SIZE + plaintext_size,
            combined + USB_AEAD_NONCE_SIZE,
            plaintext
        );
    }
    mbedtls_chachapoly_free(&crypto);
    free(combined);
    if (status != 0) {
        free(plaintext);
        return NULL;
    }
    size_t payload_size = ((size_t)plaintext[0] << 24)
        | ((size_t)plaintext[1] << 16)
        | ((size_t)plaintext[2] << 8)
        | plaintext[3];
    if (payload_size == 0 || payload_size > USB_FRAME_MAX || payload_size + 4 != plaintext_size) {
        free(plaintext);
        return NULL;
    }
    char *payload = malloc(payload_size + 1);
    if (payload == NULL) {
        free(plaintext);
        return NULL;
    }
    memcpy(payload, plaintext + 4, payload_size);
    payload[payload_size] = 0;
    free(plaintext);
    cJSON *json = cJSON_Parse(payload);
    free(payload);
    if (json != NULL) channel->receive_sequence = sequence;
    return json;
}

void usb_secure_channel_close(usb_secure_channel_t *channel)
{
    if (channel == NULL) return;
    memset(channel->key, 0, sizeof(channel->key));
    free(channel->line);
    channel->line = NULL;
    channel->line_length = 0;
    channel->line_complete = false;
    channel->authenticated = false;
    channel->pending_data = false;
}
