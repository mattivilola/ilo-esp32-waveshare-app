# ILO Board

Touch-first companion software for the Waveshare ESP32-S3-Touch-LCD-5B and macOS.

## Supported hardware

This firmware targets one exact board profile:

- **Waveshare ESP32-S3-Touch-LCD-5B**
- Waveshare SKU **28151**
- **1024×600** 5-inch capacitive-touch RGB display
- Amazon ASIN **B0DD7N19FT** — [buy the same board on Amazon.de](https://www.amazon.de/dp/B0DD7N19FT)

The no-suffix `ESP32-S3-Touch-LCD-5` (SKU 28117, 800×480) is a different display profile and is not supported by this firmware build.

The repository has two runtime halves:

- `firmware/` — ESP-IDF 5.5.2 firmware for the 1024×600 Waveshare 5B board (SKU 28151), using LVGL 9.
- `mac-service/` — a native Swift service plus a clean menu-bar companion that shows board connectivity and sends a deliberately small task-status model.

Shared wire contracts live in `protocol/`; board lifecycle tooling lives in `tools/`.

## Current phase

Phase 1 is intentionally read-only. The physical 5B display, GT911 touch, USB provisioning, Wi-Fi connection, TLS-PSK authentication, macOS menu-bar status, and recurring board snapshot delivery are hardware-verified. The current snapshot source is deterministic mock task data. The board cannot yet approve commands, apply file changes, answer Codex questions, or steer a task; those actions need a separate security and informed-consent design.

## First commands

```bash
./tools/board doctor
./tools/board chip-id
./tools/host doctor
./tools/host test
```


Install the pinned ESP-IDF toolchain and build the firmware:

```bash
./tools/setup-idf
make firmware-build
```

After the build succeeds, flash and monitor:

```bash
./tools/board flash
./tools/board monitor
```

Provision Wi-Fi and the paired Mac after the firmware is flashed:

```bash
./tools/board provision
./tools/host menu
```

`board provision` prompts for Wi-Fi details, hides the password, generates a unique 32-byte pairing key, stores the host copy in macOS Keychain, and writes only the ESP NVS data partition over the physical USB connection. Secrets are never passed as command-line arguments or written into the repository. The hardware-verified bring-up slice records the Mac's local address and fixed service port `47472`; Bonjour address discovery is the next transport increment.

`host menu` starts a menu-bar-only macOS companion with connection state, last sync, board identity, service port, security mode, and safe start/stop diagnostics. Use `./tools/host serve` for the headless development service.

### If flashing cannot connect

The board normally supports automatic download, but its native USB connection may need a manual transition:

1. Hold **BOOT**.
2. Press and release **RESET** while continuing to hold BOOT.
3. Release **BOOT**.
4. Run `./tools/board flash` again.

After a successful flash, the board may remain at `DOWNLOAD(USB/UART0)` with a black screen. Press and release **RESET once only**—do not hold BOOT—to start the flashed application. This reset does not erase or reflash anything.

See [Board bring-up](docs/board-bringup.md), [Architecture](docs/architecture.md), and [Security](docs/security.md) before flashing.

## Repository layout

```text
firmware/       ESP32-S3 board support, transport, and LVGL UI
mac-service/    SwiftPM host core, CLI, protocol, and menu-bar companion
protocol/       Versioned, language-neutral message schemas
tools/          CLI entry points for setup, build, flash, provisioning, host, backup, and recovery
docs/           Hardware, architecture, UX, and security decisions
```
