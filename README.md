# ILO Board

Touch-first companion software for the Waveshare ESP32-S3-Touch-LCD-5 and macOS.

The repository has two runtime halves:

- `firmware/` — ESP-IDF 5.5.4 firmware for the 800×480 Waveshare board, using LVGL 9.
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

See [Board bring-up](docs/board-bringup.md), [Architecture](docs/architecture.md), and [Security](docs/security.md) before flashing.

## Repository layout

```text
firmware/       ESP32-S3 board support, transport, and LVGL UI
mac-service/    SwiftPM host service and protocol implementation
protocol/       Versioned, language-neutral message schemas
tools/          CLI entry points for setup, build, flash, backup, and recovery
docs/           Hardware, architecture, UX, and security decisions
```

