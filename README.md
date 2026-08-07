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
- `mac-service/` — a native Swift service that sends a deliberately small task-status model to paired boards.

Shared wire contracts live in `protocol/`; board lifecycle tooling lives in `tools/`.

## Current phase

Phase 1 is intentionally read-only. The board may display sanitized task status, but it cannot approve commands, apply file changes, answer Codex questions, or steer a task. Those actions need a separate security and informed-consent design.

## First commands

```bash
./tools/board doctor
./tools/board chip-id
make mac-test
make mac-run
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
mac-service/    SwiftPM host service and protocol implementation
protocol/       Versioned, language-neutral message schemas
tools/          CLI entry points for setup, build, flash, backup, and recovery
docs/           Hardware, architecture, UX, and security decisions
```
