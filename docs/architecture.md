# Architecture

```text
Waveshare ESP32-S3-Touch-LCD-5B (SKU 28151, 1024x600)
  LVGL UI
  board state reducer
  framed JSON over TLS-PSK
        │ local network
        ▼
macOS user service
  board protocol + pairing
  sanitized TaskSource interface
  mock source (Phase 1)
  SwiftUI MenuBarExtra status dashboard
  SwiftUI 1024x600 device UI prototype + PNG renderer
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
- Board-specific LCD, touch, backlight, and IO-expander behavior for the 1024×600 5B stays behind `board_waveshare_5`.
- UI components consume a view model and do not perform networking.
- `BoardUIPrototype` mirrors the intended device information architecture for visual iteration and screenshots; LVGL remains the shipping device UI and physical hardware remains the final verification target.
- `BoardHostCore` owns TLS, Keychain access, task sanitization, and connection events; the menu-bar executable only presents that state and lifecycle controls.
- The macOS companion is intentionally menu-bar-only during development and uses accessory activation, so it does not add a Dock icon.

## Why ESP-IDF

Native ESP-IDF gives one supported CLI for Wi-Fi, NVS, TLS, diagnostics, serial monitoring, partitioning, and later signed OTA with rollback. The firmware pins the Waveshare-tested ESP-IDF 5.5.2 and component versions rather than inheriting a moving Arduino or PlatformIO bundle.

The hardware layer is intentionally pinned to Waveshare SKU 28151. The similarly named SKU 28117 uses an 800×480 panel with different timing and is outside this build profile.

## Why framed JSON

The first transport is a four-byte length plus JSON over TLS/TCP. It is bidirectional, bounded, debuggable, supported by Network.framework and ESP-TLS, and avoids embedding an HTTP server dependency in the macOS service. The message model can move to WebSocket later without changing dashboard records.

## Runtime configuration

Firmware never compiles Wi-Fi credentials or pairing keys into the application image. `./tools/board provision` writes them to the ESP NVS data partition through physical USB. The paired PSK is stored in the macOS login Keychain, while nonsecret board ID and service-port metadata live in `~/Library/Application Support/ILO Board Host/board.json`.

The first hardware interoperability slice uses a fixed port and provisioned LAN address. Network.framework and ESP-TLS have been verified end-to-end on the physical 5B with `TLS_PSK_WITH_AES_128_GCM_SHA256`, including recurring snapshot delivery and reconnect-visible Mac status. The Mac already advertises `_iloboard._tcp`; firmware-side Bonjour browsing is the next transport increment.

Weather may later use a separate direct-board HTTPS path so it survives a Mac reboot or absence. That path is restricted to purpose-built public-data clients; it does not change the rule that Codex credentials and the App Server stay on the Mac.
