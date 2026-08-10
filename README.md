# ILO Board

Touch-first companion software for the Waveshare ESP32-S3-Touch-LCD-5B and macOS.

> **macOS download:** [Download the latest notarized universal DMG](https://storage.googleapis.com/ilo-public/ilo-board/ILOBoard-latest.dmg) for macOS 13 or newer. Move **ILO Board.app** to Applications after opening the DMG; future releases can then update in place through the signed Sparkle feed.

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

Phase 1 keeps Codex and Mac control read-only. The only board-originated action is a narrowly bounded, rate-limited X News refresh request that still requires prior Mac-side opt-in. The physical 5B display, GT911 touch, USB provisioning, Wi-Fi connection, TLS-PSK authentication, macOS menu-bar status, and recurring board snapshot delivery are hardware-verified. The Mac companion now reads real recent task history through the supported local Codex App Server and shares only a bounded MacBook battery percentage/charging state; deterministic mock task data remains available for demos and tests. Delivering those new sources to the board has not yet been rechecked on hardware. The five-page LVGL navigation, shared icon, persistent Settings, Work Pulse timer/clock, screensaver/backlight sleep, direct HTTPS weather, optional Mac-verified X News feed/pull-to-refresh, and Mac power card are firmware-compiled but also await the next physical hardware session. The board cannot yet approve commands, apply file changes, answer Codex questions, or steer a task; those actions need a separate security and informed-consent design.

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
- Optional X News integration: `grok` CLI 1.0.0 or a compatible newer build, authenticated with an account that can search X. Set `ILO_BOARD_GROK_PATH` if it is not on `PATH` or under `~/.local/bin`. Grok authentication remains on the Mac.

### Network

- The Mac and board must be able to reach each other on the same LAN.
- Client/AP isolation must be disabled.
- Bonjour discovery requires multicast DNS between clients. Firmware now looks for the paired Mac's `_iloboard._tcp` instance, accepts only protocol-v1 `tls-psk-tcp` TXT metadata, and otherwise retains the provisioned Mac address as a recovery fallback. This path is compile-verified and awaits a physical LAN/reconnect test.
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

`board provision` prompts for Wi-Fi details, a recovery Mac address, and weather location/coordinates; it hides the Wi-Fi password, generates a unique 32-byte pairing key, stores the host copy in macOS Keychain, and writes only the ESP NVS data partition over the physical USB connection. Secrets are never passed as command-line arguments or written into the repository. At runtime the board first discovers the paired host's compatible Bonjour service and uses its current address and advertised port. If multicast DNS is unavailable, incompatible, or does not return that host, it safely falls back to the provisioned address and port.

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
| Inspect OTA safety gates | `make ota-status` | No |
| Verify a signed OTA artifact | `./tools/board ota-verify --image IMAGE --public-key PUBLIC.pem --sdkconfig SDKCONFIG` | No |
| Open interactive 1024×600 UI preview | `make ui-preview` | No |
| Export all five simulator screenshots | `make ui-screenshots` | No |
| Export one simulator screenshot | `./tools/board ui-screenshot --screen codex` | No |
| Identify chip | `./tools/board chip-id` | Yes, USB |
| Back up the complete 16 MB flash | `./tools/board backup` | Yes, USB |
| Securely provision Wi-Fi/pairing | `./tools/board provision` | Yes, USB |
| Reboot from download mode | `./tools/board reboot` | Yes, USB |
| Build the Swift package | `make mac-build` | No |
| Test the Swift host/protocol | `make mac-test` | No |
| Inspect one sanitized status snapshot | `./tools/host snapshot` | No |
| Run the menu-bar app from source | `make mac-menu` | No; board status stays offline |
| Run the headless Codex service | `make mac-run` or `./tools/host serve` | No; board status stays offline |
| Run the service with sample tasks | `./tools/host serve --mock` | No |
| Inspect optional X News state | `./tools/host x-news status` | No |
| Fetch a verified rolling 24h X feed | `./tools/host x-news refresh --allow-grok-tools` | No |
| Enable daily X News | `./tools/host x-news enable --allow-grok-tools` | No |
| Capture the live board framebuffer | `./tools/host screenshot --output board.png` | Yes, Wi-Fi |
| Build universal `.app` | `make app` | No |
| Build local DMG | `make package-dmg` | No |
| Show release version/build | `make release-version` | No |
| Prepare next patch release | `make version-patch` | No |
| Build and notarize release | `make release-local` | No |
| Upload DMGs and signed Sparkle feed | `make release-distribute` | No |
| Run every hardware-independent test | `make test` | No |
| Test host/release tooling and compile firmware | `make verify` | No |

`./tools/board --help` and `./tools/host --help` are the authoritative detailed command lists.

### OTA foundation

The partition table already reserves equal 4 MiB `ota_0` and `ota_1` slots. Rollback is enabled for clean builds, and a newly installed image stays `PENDING_VERIFY` until board/UI initialization succeeds and a 30-second runtime/heap health window passes. A crash, reset, failed health check, or failure to persist the valid state keeps the image unconfirmed and selects the previous valid slot when recovery is available.

There is deliberately no OTA upload or install command yet. `make ota-status` is read-only and reports the current layout, rollback, and signing gates. Production artifacts must use the separate signed-update profile and pass `ota-verify`; that command accepts only a public RSA key, validates the ESP image and release sdkconfig, verifies the Secure Boot v2 signature, and prints its SHA-256 without uploading anything. Private signing keys must remain outside this repository. See [the OTA policy](docs/ota.md) for the release flow and remaining hardware gates.

### Screenshots

Open the interactive desktop representation with `make ui-preview`. Swipe horizontally with the trackpad, drag with the pointer, or click Dashboard/Codex/X News/Weather/Settings. The X News page scrolls vertically; pull down while already at the top to preview its refresh states. Closing the preview window also stops the underlying Swift/Python command and returns the terminal prompt. Export deterministic 1024×600 PNGs with:

```bash
make ui-screenshots
./tools/board ui-screenshot --screen settings --output /tmp/ilo-settings.png
```

Generated files go to `artifacts/ui-previews/` by default. They use sample data and represent the intended layout. They do not prove RGB output, physical legibility, touch mapping, backlight behavior, or frame timing.

The updated firmware also supports an authenticated live framebuffer capture:

```bash
# Stop the menu companion first so the capture host can use its service port.
./tools/host screenshot --output /tmp/ilo-board-live.png
```

The command waits up to 45 seconds for the paired board, requests exactly one 1024×600 RGB565-LE frame over the existing TLS-PSK connection, verifies 100 strictly ordered bounded chunks and the final SHA-256 digest, then writes a PNG atomically. It refuses to replace an existing file unless `--force` is explicit; `--timeout 1..120` changes the wait. There is no HTTP screenshot endpoint and an unpaired LAN client cannot request a capture. Firmware, protocol validation, worst-case frame sizing, RGB565 conversion, and PNG dimensions are hardware-independently verified. Actual panel color order, buffer freshness, tearing, capture latency, and peak PSRAM still require the physical board.

### Five-screen information architecture

1. **Dashboard** — the glanceable work pulse: attention count, active work, connection state, and current focus.
2. **Codex** — recent sanitized task status and a visible read-only safety boundary.
3. **X News** — an optional rolling 24-hour AI/robotics brief containing only locally validated direct X citations. Vertically scroll up to five stories; horizontal swipes still move between screens.
4. **Weather** — current/near-term conditions, clearly labeling sample, stale, or offline data.
5. **Settings** — display power, screensaver, connectivity, privacy, and safe setup routes.

The page order is fixed and tested. Horizontal swipe is the primary page gesture, while the always-visible bottom navigation provides discovery and direct access. On X News, direction-aware gesture handling reserves vertical drags for the story feed and lets horizontal drags continue to Weather or Codex. A compact “more” cue appears only when the feed exceeds the first three visible stories. Pull down from the top to request a refresh; the board shows pull/release/fetching/result states rather than freezing the old content or claiming success early.

These are deterministic desktop renders with sample data, not photographs of the physical panel:

<p align="center">
  <img src="docs/images/ui-preview/dashboard.png" alt="ILO Board Dashboard simulator screen" width="49%">
  <img src="docs/images/ui-preview/codex.png" alt="ILO Board Codex simulator screen" width="49%">
</p>
<p align="center">
  <img src="docs/images/ui-preview/x-news.png" alt="ILO Board X News simulator screen" width="49%">
  <img src="docs/images/ui-preview/weather.png" alt="ILO Board Weather simulator screen" width="49%">
</p>
<p align="center">
  <img src="docs/images/ui-preview/settings.png" alt="ILO Board Settings simulator screen" width="49%">
</p>

The Settings screen now cycles and persists the clock format (12/24 hour), temperature units, focus duration (25/45/60 minutes), Pulse screensaver timeout (`Never`, 2, or 5 minutes), display-off timeout (`Never`, 5, 10, or 30 minutes), and whether task summaries are visible. It also offers **Turn display off now**. Settings live in their own NVS namespace and survive normal reboot/firmware updates; full USB reprovisioning replaces the NVS partition and returns them to defaults. Wi-Fi password editing remains in secure USB provisioning until an equally safe on-device flow exists.

The matching LVGL structure is already compiled into firmware, including horizontal tile gestures, persistent setting controls, the embedded ILO roundel, a moving Pulse saver, binary backlight sleep, and a wake touch that is consumed rather than passed through to a hidden control. Do not treat it as hardware-verified yet: swipe behavior, text clipping, icon alpha/color order, CH422G backlight off/on, timeout/wake behavior, and real touch targets must be checked on the 5B before flashing this build is called stable.

An old-school screensaver does make sense here as a product feature: the ILO roundel and status move slowly around the screen. Because this is an LCD rather than OLED, its main benefits are ambience and glanceability; actual power savings come when the backlight is switched off. The exact 5B exposes `DISP` as a binary CH422G expander output, not a PWM brightness channel, so the UX does not promise a fake brightness slider.

## Connecting to Codex

The implemented supported boundary is the local Codex App Server, launched on demand by the Mac companion over its JSONL/stdio transport. The board never receives your ChatGPT authentication, API key, full prompts, transcript, working-directory paths, or file contents.

Check the local prerequisite with:

```bash
codex --version
codex login status
./tools/host doctor
./tools/host snapshot
```

`snapshot` prints exactly the bounded task, X News, and Mac power payload that would be sent to a paired board. Use `./tools/host snapshot --mock` or `./tools/host serve --mock` for deterministic sample tasks and a simulated charging MacBook. The menu app and headless service use real Codex history and native Mac power data by default.

The packaged menu app searches `PATH`, `/opt/homebrew/bin/codex`, and `/usr/local/bin/codex`. If Codex lives elsewhere, launch it with `ILO_BOARD_CODEX_PATH=/absolute/path/to/codex`. The adapter has been integration-tested with `codex-cli 0.146.0`; its decoder is deliberately narrow, but a materially changed future App Server schema may require an update.

The first real adapter is intentionally read-only:

- `thread/list` supplies at most six recent task names, timestamps, and coarse status through the installed Codex CLI.
- Board-visible strings are bounded and sanitized before transport.
- The adapter decodes only thread ID, optional name, update time, and status; prompts, previews, turns, paths, source metadata, and file contents are ignored.
- A separately launched App Server can truthfully list recent stored tasks, including tasks created in Codex Desktop.
- Codex Desktop-owned tasks currently appear as `notLoaded` to that separate server, so it cannot truthfully claim their live running, approval, or question state.
- Authoritative live status is available only for tasks loaded/owned by the companion's App Server until OpenAI exposes a supported Desktop attachment.
- Remote answers, approvals, command execution, and task steering remain disabled in Phase 1.

Do not copy Codex credentials into firmware or NVS. Any future write/control capability must be separately paired, narrowly scoped, visibly confirmed, replay-protected, and auditable.

## Optional X News via Grok

X News is Mac-mediated and disabled by default. It uses the authenticated top-level headless command `grok -p`; it does not use `grok agent`, and no Grok/X credential is copied to the board. Check availability and the last verified cache with:

```bash
grok --version
./tools/host x-news status
```

A manual refresh is explicit because Grok may use paid model/tool capacity:

```bash
./tools/host x-news refresh --allow-grok-tools
```

Enable one automatic run at 08:00 local each day, optionally adding a 14:00 run, or disable it without deleting the last verified cache:

```bash
./tools/host x-news enable --allow-grok-tools
./tools/host x-news enable --twice-daily --allow-grok-tools
./tools/host x-news disable
```

The scheduler runs while the menu companion or headless host is running. Manual and failed scheduled attempts are rate-limited, so a failure is not retried every minute. Each request supplies a rolling UTC `since`/`until` window, asks Grok to use keyword and semantic X search, requests 2–5 AI/robotics stories, and preserves only a bounded cache.

The paired board can request that same manual refresh by pulling down at the top of X News. This works only after X News has been explicitly enabled on the Mac, and it still enforces the 15-minute cooldown and one in-flight Grok process. The board receives bounded `fetching`, `updated`, `disabled`, `cooldown`, `busy`, or `failed` state—not Grok output or error details. An accepted refresh appears on the next five-second snapshot; a rejected refresh leaves the previous verified feed unchanged.

The JSON schema is treated as a hint, not a trust boundary. The Mac independently requires high/medium confidence, bounded single-line text, 1–3 matching `@handle` citations per story, and direct `https://x.com/<handle>/status/<id>` URLs. It decodes the X status ID timestamp and drops stories outside the requested 24 hours or inconsistent with `posted_at`; at least two fully verified stories must survive or the complete refresh is rejected. If Grok concatenates multiple documents, only documents with a valid rolling window and enough verified stories participate; the final document has priority, then duplicate headlines/citation URLs and already-cached sources are removed before the result is capped at five. Invalid, unsourced, oversized, stale, or future output never replaces the last good feed. The board receives only the verified cache, not Grok reasoning, session IDs, usage, prompts, or credentials.

The local Grok 1.0.0 tests proved why this gate is necessary: the schema-based attempts still reported structured-output errors; one returned only root X URLs, while the improved prompt found direct posts but concatenated two JSON documents. The adapter therefore fails closed instead of trusting `--json-schema` by itself.

## Internet access without the Mac

Yes. Once the updated firmware has been flashed and `./tools/board provision` has stored a weather name/latitude/longitude, the board reconnects to known Wi-Fi after reboot and fetches weather without the Mac. It synchronizes time before TLS, validates HTTPS with the ESP-IDF certificate bundle, requests current conditions plus a three-day forecast, refreshes every 30 minutes, retries failures after one minute, and labels retained data `STALE` instead of silently presenting it as current. This logic is compile-verified and its exact JSON contract has been checked against the live API, but it still needs a physical-board network test.

The development endpoint is the keyless Open-Meteo free API. The Weather screen includes the required attribution. Open-Meteo says its free endpoint is for non-commercial use; a commercial release must use an appropriate subscription/customer endpoint or another licensed provider. See the [forecast API](https://open-meteo.com/en/docs), [licence/attribution](https://open-meteo.com/en/license), and [terms](https://open-meteo.com/en/terms).

Direct Codex control is a different security class. Codex App Server runs locally on the Mac and the ESP32 should not hold ChatGPT credentials or expose a general command channel. Codex status/control therefore remains Mac-mediated. The board can still show its last safe cached snapshot when the Mac is offline.

## macOS packaging and public releases

The source icon is used in the menu dashboard and converted into the packaged app's `.icns`. `make app` creates an ad-hoc-signed universal Apple Silicon + Intel bundle at `artifacts/ILO Board.app`; `make package-dmg` creates a local DMG. These are developer artifacts, not public releases. The menu dashboard shows the installed version/build and offers **Check for Updates…** in signed builds.

For Developer ID signing, Apple notarization, Sparkle EdDSA signing, and Google Cloud Storage delivery, follow [macOS distribution](docs/macos-distribution.md). The release pipeline refuses to upload unless the versioned DMG has a valid stapled notarization ticket, the stable alias is byte-for-byte identical, and a signed appcast with bounded `CHANGELOG.md` history can be generated. No credentials are committed, `make release-local` never uploads, and GCS writes happen only when `make release-distribute` is run explicitly. The versioned DMG and stable alias are uploaded before `appcast.xml`, so clients never discover an unavailable archive.

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
