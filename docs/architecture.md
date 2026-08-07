# Architecture

```text
Waveshare ESP32-S3
  LVGL UI
  board state reducer
  framed JSON over TLS-PSK
        │ local network
        ▼
macOS user service
  board protocol + pairing
  sanitized TaskSource interface
  mock source (Phase 1)
  service-owned Codex adapter (later)
        │ stdio / local Unix socket only
        ▼
Codex app-server
```

## Boundaries

- The ESP32 never receives OpenAI credentials, Mac login credentials, full transcripts, shell access, filesystem paths, or environment variables.
- `BoardProtocol` contains transport-neutral status models.
- `TaskSource` isolates Codex from the board-facing service. The initial source is deterministic mock data.
- A future Codex source may observe only threads owned by its own documented `codex app-server` connection. It must not label unrelated desktop chats as live.
- Board-specific LCD, touch, backlight, and IO-expander behavior stays behind `board_waveshare_5`.
- UI components consume a view model and do not perform networking.

## Why ESP-IDF

Native ESP-IDF gives one supported CLI for Wi-Fi, NVS, TLS, diagnostics, serial monitoring, partitioning, and later signed OTA with rollback. The firmware pins ESP-IDF 5.5.4 and component versions rather than inheriting a moving Arduino or PlatformIO bundle.

## Why framed JSON

The first transport is a four-byte length plus JSON over TLS/TCP. It is bidirectional, bounded, debuggable, supported by Network.framework and ESP-TLS, and avoids embedding an HTTP server dependency in the macOS service. The message model can move to WebSocket later without changing dashboard records.

