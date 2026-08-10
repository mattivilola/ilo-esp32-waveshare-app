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
  Codex recent-history source (default)
  deterministic mock source (tests/demos)
  SwiftUI MenuBarExtra status dashboard
  SwiftUI 1024x600 device UI prototype + PNG renderer
        │ one-shot JSONL/stdio
        ▼
Codex app-server
```

## Boundaries

- The ESP32 never receives OpenAI credentials, Mac login credentials, full transcripts, shell access, filesystem paths, or environment variables.
- `BoardProtocol` contains transport-neutral status models.
- `TaskSource` isolates Codex from the board-facing service. `CodexHistoryTaskSource` is the default; deterministic mock data remains an explicit test/demo mode.
- The Codex source starts a local App Server only for a bounded `thread/list` request, caches the result for 15 seconds, then closes the child process. It uses the supported protocol instead of scraping Codex databases or session files.
- The separately launched server can list recent Desktop-created tasks, but those tasks report `notLoaded`; the mapper labels them as recent history and never as live. Only tasks loaded by that App Server may expose authoritative active/waiting state.
- The narrow decoder admits only thread ID, name, update time, and status. Board payloads exclude prompt preview, working directory, turns, source metadata, Git data, and file contents.
- Board-specific LCD, touch, backlight, and IO-expander behavior for the 1024×600 5B stays behind `board_waveshare_5`.
- User display/privacy settings live in the separate `ilo_settings` NVS namespace. Normal app flashes and reboots preserve them; the deliberate full-NVS USB provisioning flow resets them with the rest of provisioned state.
- The 5B `DISP` line is a binary CH422G output. `board_waveshare_5` therefore exposes backlight on/off only; no firmware layer pretends that PWM brightness is available.
- UI components consume a view model and do not perform networking.
- `BoardUIPrototype` mirrors the intended device information architecture for visual iteration and screenshots; LVGL remains the shipping device UI and physical hardware remains the final verification target.
- The shared 512×512 PNG is transformed deterministically into macOS `.icns` and a 48×48 LVGL ARGB descriptor by `make assets`; generated firmware bytes contain no runtime PNG decoder dependency.
- `BoardHostCore` owns TLS, Keychain access, task sanitization, and connection events; the menu-bar executable only presents that state and lifecycle controls.
- Live screenshots reuse the authenticated framed connection. A one-shot host sends a versioned capture request only after hello/subscription, firmware copies one full LVGL RGB565 buffer into temporary PSRAM, and returns bounded base64 chunks plus SHA-256. The host validates metadata, exact sequence/offset/length, and checksum before converting to PNG; neither side exposes an HTTP listener.
- The macOS companion is intentionally menu-bar-only during development and uses accessory activation, so it does not add a Dock icon.

## Why ESP-IDF

Native ESP-IDF gives one supported CLI for Wi-Fi, NVS, TLS, diagnostics, serial monitoring, partitioning, and later signed OTA with rollback. The firmware pins the Waveshare-tested ESP-IDF 5.5.2 and component versions rather than inheriting a moving Arduino or PlatformIO bundle.

The hardware layer is intentionally pinned to Waveshare SKU 28151. The similarly named SKU 28117 uses an 800×480 panel with different timing and is outside this build profile.

## Why framed JSON

The first transport is a four-byte length plus JSON over TLS/TCP. It is bidirectional, bounded, debuggable, supported by Network.framework and ESP-TLS, and avoids embedding an HTTP server dependency in the macOS service. The message model can move to WebSocket later without changing dashboard records.

## Runtime configuration

Firmware never compiles Wi-Fi credentials or pairing keys into the application image. `./tools/board provision` writes them to the ESP NVS data partition through physical USB. The paired PSK is stored in the macOS login Keychain, while nonsecret board ID and service-port metadata live in `~/Library/Application Support/ILO Board Host/board.json`.

Network.framework and ESP-TLS have been verified end-to-end on the physical 5B with `TLS_PSK_WITH_AES_128_GCM_SHA256`, including recurring snapshot delivery and reconnect-visible Mac status. The Mac advertises `_iloboard._tcp`; firmware now queries that service before each connection attempt, selects only the instance derived from the provisioned board identity, requires TXT `v=1` and `transport=tls-psk-tcp`, and uses the returned IPv4 address and service port. If mDNS initialization, lookup, compatibility checks, or address resolution fail, transport uses the provisioned LAN address and port unchanged. TLS-PSK plus the protocol hello still provide the authoritative board identity check after endpoint selection. Bonjour selection is compile-verified but not yet exercised on the physical board.

Weather uses a separate direct-board HTTPS path so it survives a Mac reboot or absence. The client waits for the shared station-mode Wi-Fi connection, synchronizes wall time with SNTP, validates the server through ESP-IDF's certificate bundle, bounds the body to 8 KiB, parses only the selected current/daily fields, and refreshes every 30 minutes. LIVE/STALE/OFFLINE/SETUP NEEDED are distinct UI states. This purpose-built public-data client does not change the rule that Codex credentials and the App Server stay on the Mac.
