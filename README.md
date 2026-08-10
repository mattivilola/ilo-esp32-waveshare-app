# ILO Board

Touch-first companion software for the Waveshare ESP32-S3-Touch-LCD-5B and macOS.

> **macOS download:** the stable public URL is reserved, but no notarized public build has been published yet. Until the first release, build locally with `make app`. The download button will be enabled only after `make release-distribute` has successfully published and the URL has been verified.

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

Phase 1 is intentionally read-only. The physical 5B display, GT911 touch, USB provisioning, Wi-Fi connection, TLS-PSK authentication, macOS menu-bar status, and recurring board snapshot delivery are hardware-verified. The current snapshot source is deterministic mock task data. The four-page LVGL navigation, shared icon, Weather/Settings surfaces, and Pulse screensaver are firmware-compiled but await the next physical hardware session. The board cannot yet approve commands, apply file changes, answer Codex questions, or steer a task; those actions need a separate security and informed-consent design.

Hardware-independent development can continue without a board: the Swift service and tests, universal `.app`/DMG packaging, protocol work, generated UI assets, firmware compilation, and desktop UI previews do not require a connected display. Flashing, live touch behavior, RGB timing, backlight control, Wi-Fi behavior, power use, and actual-device screenshots remain hardware verification gates.

## Requirements

### Hardware

- Waveshare **ESP32-S3-Touch-LCD-5B**, SKU **28151**, 1024×600. The 800×480 no-suffix board is not compatible.
- A data-capable USB-C cable. A charge-only cable can power the display but cannot flash or provision it.
- Direct Mac USB or a powered hub capable of supplying the display reliably. Keep the board's battery switch **off** during USB debugging.
- A 2.4 GHz WPA2/WPA3 Personal Wi-Fi network for wireless operation. The ESP32-S3 does not use a 5 GHz-only network.

### Mac development machine

- macOS 13 Ventura or newer. Development is currently verified on macOS 15.7.7.
- Xcode Command Line Tools or Xcode with Swift 6.2-compatible tooling: `xcode-select --install`.
- Git, CMake, Ninja, and Python 3. The pinned ESP-IDF installer reports anything missing.
- macOS Keychain access. Pairing stores the per-board TLS secret in the login Keychain; the prompt expects your normal Mac login password.
- Local Network permission for the packaged menu-bar app.
- For Codex integration: a supported local `codex` CLI that is installed and authenticated. No Codex token is stored on the board.

### Network

- The Mac and board must be able to reach each other on the same LAN.
- Client/AP isolation must be disabled.
- Bonjour discovery requires multicast DNS between clients; the provisioned Mac address remains a recovery fallback while discovery support is completed.
- Wi-Fi provisioning currently accepts WPA2/WPA3 Personal passwords of 8–63 UTF-8 bytes. Enterprise and open Wi-Fi are not supported yet.

## Quick start

```bash
make help
make firmware-setup
make firmware-build
make mac-test

./tools/board doctor
./tools/board chip-id
./tools/host doctor
```

`firmware-build`, `mac-build`, `mac-test`, `app`, and the release-tool checks are useful without physical hardware. Commands that query, flash, provision, reboot, monitor, or capture a real board require USB or Wi-Fi access to the board.

### First board setup

```bash
./tools/setup-idf
make firmware-build
./tools/board backup
./tools/board flash
./tools/board provision
./tools/host menu
```

`board provision` prompts for Wi-Fi details, hides the password, generates a unique 32-byte pairing key, stores the host copy in macOS Keychain, and writes only the ESP NVS data partition over the physical USB connection. Secrets are never passed as command-line arguments or written into the repository. The hardware-verified bring-up slice records the Mac's local address and fixed service port `47472`; Bonjour address discovery is the next transport increment.

`host menu` starts a menu-bar-only macOS companion with connection state, last sync, board identity, service port, security mode, and safe start/stop diagnostics. Use `./tools/host serve` for the headless development service.

When macOS asks whether `ILOBoardMenu` may use the confidential `com.iloapps.iloboard.host.psk` item, enter your normal Mac login password. **Always Allow** is appropriate for the paired menu-bar app; **Allow** grants only the current access.

## Command reference

There is no Node/npm layer in this repository. The stable entry points are `make`, `./tools/board`, and `./tools/host`.

| Goal | Command | Board required |
| --- | --- | --- |
| Show all common commands | `make help` | No |
| Regenerate shared macOS/firmware icon assets | `make assets` | No |
| Check local prerequisites and USB detection | `make doctor` | Only for USB status |
| Install pinned ESP-IDF 5.5.2 | `make firmware-setup` | No |
| Compile firmware | `make firmware-build` | No |
| Flash firmware | `make firmware-flash` | Yes, USB |
| Open serial monitor | `make firmware-monitor` | Yes, USB |
| Open interactive 1024×600 UI preview | `make ui-preview` | No |
| Export all four simulator screenshots | `make ui-screenshots` | No |
| Export one simulator screenshot | `./tools/board ui-screenshot --screen codex` | No |
| Identify chip | `./tools/board chip-id` | Yes, USB |
| Back up the complete 16 MB flash | `./tools/board backup` | Yes, USB |
| Securely provision Wi-Fi/pairing | `./tools/board provision` | Yes, USB |
| Reboot from download mode | `./tools/board reboot` | Yes, USB |
| Build the Swift package | `make mac-build` | No |
| Test the Swift host/protocol | `make mac-test` | No |
| Run the menu-bar app from source | `make mac-menu` | No; board status stays offline |
| Run the headless development service | `make mac-run` | No; board status stays offline |
| Build universal `.app` | `make app` | No |
| Build local DMG | `make package-dmg` | No |
| Run every hardware-independent test | `make test` | No |
| Test host/release tooling and compile firmware | `make verify` | No |

`./tools/board --help` and `./tools/host --help` are the authoritative detailed command lists.

### Screenshots

Open the interactive desktop representation with `make ui-preview`. Swipe horizontally with the trackpad, drag with the pointer, or click Dashboard/Codex/Weather/Settings. Export deterministic 1024×600 PNGs with:

```bash
make ui-screenshots
./tools/board ui-screenshot --screen settings --output /tmp/ilo-settings.png
```

Generated files go to `artifacts/ui-previews/` by default. They use sample data and represent the intended layout. They do not prove RGB output, physical legibility, touch mapping, backlight behavior, or frame timing.

There is not yet a live `board screenshot` framebuffer command in the flashed firmware. Until that transport exists, a photo is the only faithful capture of the actual panel.

### Four-screen information architecture

1. **Dashboard** — the glanceable work pulse: attention count, active work, connection state, and current focus.
2. **Codex** — recent sanitized task status and a visible read-only safety boundary.
3. **Weather** — current/near-term conditions, clearly labeling sample, stale, or offline data.
4. **Settings** — display power, screensaver, connectivity, privacy, and safe setup routes.

The page order is fixed and tested. Horizontal swipe is the primary gesture, while the always-visible bottom navigation provides discovery and direct access.

These are deterministic desktop renders with sample data, not photographs of the physical panel:

<p align="center">
  <img src="docs/images/ui-preview/dashboard.png" alt="ILO Board Dashboard simulator screen" width="49%">
  <img src="docs/images/ui-preview/codex.png" alt="ILO Board Codex simulator screen" width="49%">
</p>
<p align="center">
  <img src="docs/images/ui-preview/weather.png" alt="ILO Board Weather simulator screen" width="49%">
  <img src="docs/images/ui-preview/settings.png" alt="ILO Board Settings simulator screen" width="49%">
</p>

The first settings surface covers brightness, idle dim timeout, screen-off timeout, screensaver mode, Wi-Fi/Mac/weather status, and privacy mode. Wi-Fi password editing remains in secure USB provisioning until an equally safe on-device flow exists.

The matching LVGL structure is already compiled into firmware, including horizontal tile gestures and the embedded ILO roundel. Do not treat it as hardware-verified yet: swipe behavior, memory headroom, text clipping, icon alpha/color order, screensaver timeout/wake, and real touch targets must be checked on the 5B before flashing this build is called stable.

An old-school screensaver does make sense here as a product feature: a slow pulse clock with the ILO roundel and one small status indicator. Because this is an LCD rather than OLED, its main benefits are ambience and glanceability; actual power savings come from dimming or switching off the backlight.

## Connecting to Codex

The planned supported boundary is the local Codex App Server, launched by the Mac companion over its default JSONL/stdio transport. The board never receives your ChatGPT authentication, API key, full prompts, transcript, working-directory paths, or file contents.

Check the local prerequisite with:

```bash
codex --version
codex login status
```

The first real adapter is intentionally read-only:

- `thread/list` supplies recent task names, timestamps, and status through the exact schema generated by the installed Codex CLI.
- Board-visible strings are bounded and sanitized before transport.
- A separately launched App Server can truthfully list recent stored tasks, including tasks created in Codex Desktop.
- Codex Desktop-owned tasks currently appear as `notLoaded` to that separate server, so it cannot truthfully claim their live running, approval, or question state.
- Authoritative live status is available only for tasks loaded/owned by the companion's App Server until OpenAI exposes a supported Desktop attachment.
- Remote answers, approvals, command execution, and task steering remain disabled in Phase 1.

Do not copy Codex credentials into firmware or NVS. Any future write/control capability must be separately paired, narrowly scoped, visibly confirmed, replay-protected, and auditable.

## Internet access without the Mac

Yes, the board can reconnect to stored Wi-Fi after reboot and make direct HTTPS requests. Direct weather is a sensible standalone feature once certificate/time synchronization, caching, location settings, rate limiting, and offline behavior are implemented. The Mac can be absent for that path.

Direct Codex control is a different security class. Codex App Server runs locally on the Mac and the ESP32 should not hold ChatGPT credentials or expose a general command channel. Codex status/control therefore remains Mac-mediated. The board can still show its last safe cached snapshot when the Mac is offline.

## macOS packaging and public releases

The source icon is used in the menu dashboard and converted into the packaged app's `.icns`. `make app` creates an ad-hoc-signed universal Apple Silicon + Intel bundle at `artifacts/ILO Board.app`; `make package-dmg` creates a local DMG. These are developer artifacts, not public releases.

For Developer ID signing, Apple notarization, and Google Cloud Storage delivery, follow [macOS distribution](docs/macos-distribution.md). The release pipeline refuses to upload unless the versioned DMG has a valid stapled notarization ticket and the stable alias is byte-for-byte identical. No credentials are committed, and GCS upload happens only when `make release-distribute` is run explicitly.

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
