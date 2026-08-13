# Waveshare 5B physical validation gate

This checklist is the release gate for the **Waveshare ESP32-S3-Touch-LCD-5B, SKU 28151, 1024×600**. It does not apply to the 800×480 no-suffix board. Every item below is currently **NOT RUN** for the post-travel firmware unless an evidence link and tested commit are added to the result record.

Do not mark the firmware hardware-verified merely because it compiles, renders in the SwiftUI fixture, or worked with an older binary. Perform the gate against the exact commit proposed for release.

## Result record

Copy this block into the release notes or test log and fill it during the session:

```text
Board: Waveshare ESP32-S3-Touch-LCD-5B / SKU 28151 / 1024x600
Firmware commit:
Firmware version/build:
Mac model and macOS version:
Mac companion version/build:
Wi-Fi/router:
Started (local time):
Completed (local time):
Tester:
Overall: NOT RUN | PASS | FAIL
Evidence folder:
Failed check IDs:
Notes:
```

Never put the Wi-Fi password, pairing secret, complete board ID, local IP address, Codex prompt, transcript, or private path in the evidence folder.

## Prerequisites

- A data-capable USB-C cable, the factory 16 MB backup, and the exact 5B board are available.
- The board is powered only by USB for the first pass; any battery switch is off.
- `make verify` passes at the exact commit under test.
- `./tools/board doctor` shows one expected `/dev/cu.usbmodem*` device.
- `./tools/board chip-id` identifies an ESP32-S3; the cold-boot log agrees with the board's documented 16 MB flash/8 MB PSRAM profile.
- The board has been provisioned through `./tools/board provision`; secrets have not been copied into the repository or test notes.
- A phone or camera is ready for panel evidence. Simulator screenshots are reference fixtures, not panel captures.

## A. Identity, boot, and panel

| ID | Procedure | Pass condition | Evidence | Result |
| --- | --- | --- | --- | --- |
| HW-001 | Photograph the product label/PCB, run `./tools/board chip-id`, and retain the cold-boot memory lines. | Label/profile is 5B/SKU 28151; chip is ESP32-S3; boot log agrees with the documented 16 MB flash/8 MB PSRAM profile. | Redacted photo + terminal excerpt | NOT RUN |
| HW-002 | Cold boot from disconnected USB while serial monitoring is ready. | One normal boot reaches Dashboard without a reset loop, panic, watchdog, or ROM download prompt. | Complete redacted boot log | NOT RUN |
| HW-003 | Compare Dashboard, Codex, X News, Weather, and Settings with `docs/images/ui-preview/`. | Content fills 1024×600; no 800×480 crop/stretch, tearing, unexpected rotation, or edge offset. | One straight-on photo per page | NOT RUN |
| HW-004 | Inspect the ILO roundel, mint bar, amber states, text, gradients/shadows, and dark cards. | Icon alpha is clean; red/blue channels are not swapped; text is legible; no persistent corruption or flicker. | Close-up photo | NOT RUN |
| HW-005 | Leave the normal Dashboard visible for 15 minutes. | No panel corruption, visible frame jitter, reset, or growing redraw artifact. | Start/end photo + serial log | NOT RUN |

## B. Touch and page navigation

| ID | Procedure | Pass condition | Evidence | Result |
| --- | --- | --- | --- | --- |
| HW-101 | Tap each bottom navigation target five times, including near each target's left/right edges. | 20/20 intended taps select the correct page; adjacent pages are never selected. | Short video + count | NOT RUN |
| HW-102 | With no Mac configured, swipe Dashboard → Weather → Settings and back ten times. Pair Codex and repeat through Dashboard → Codex → Weather → Settings. Enable X News, repeat through all five pages, then disable an optional page while it is open. | Navigation expands from three to four to five pages and contracts without a gap, wrap, stuck tile, inverted gesture, or hidden selected page; removing the open optional page lands safely on Weather. The standalone Dashboard contains useful weather/device controls and no fabricated Codex data. | Video + cycle count | NOT RUN |
| HW-103 | Make mostly vertical drags over cards and Settings controls. | Vertical intent does not unexpectedly change page; a control changes only when deliberately tapped. | Video | NOT RUN |
| HW-104 | Exercise every Settings row and privacy toggle, then return to each page. | Hit targets respond once per tap, labels update, content stays clipped to its cards, and navigation remains available. | Video + values tested | NOT RUN |
| HW-105 | Reboot after changing every persisted setting. | Screensaver timeout, display-off timeout, and privacy state survive a normal reboot. | Before/after photos + boot log | NOT RUN |
| HW-106 | Switch 24-hour/12-hour clock, Celsius/Fahrenheit, and 25/45/60-minute focus duration, rebooting after the final choice. | Header/screensaver format and every weather temperature use the selected units; focus duration and all choices survive reboot. | Before/after photos + chosen values | NOT RUN |
| HW-107 | Hold the 25-minute Settings row to start, pause/resume, add five minutes, reset during the run, and let a shortened development session reach zero. Also hold a Codex row to attach it and hold End to cancel a separate run. | Focus Cockpit opens only after the hold; countdown/deadline and pause state survive reset through NVS + RTC; +5 extends exactly five minutes; natural completion is explicit and can notify the paired Mac once; early End does not claim completion; task text is not retained after reboot. | Timed video + serial log + Mac notification | NOT RUN |

## C. Failure and privacy states

Use [the deterministic state gallery](ui-state-validation.md) as a semantic reference. Pixel identity with SwiftUI is not required; the LVGL result must preserve the hierarchy, wording intent, state color, attribution, and safe truncation.

| ID | Procedure | Pass condition | Evidence | Result |
| --- | --- | --- | --- | --- |
| HW-201 | Stop the Mac host while the board is online. | The board changes to an unambiguous offline state, retains only safe cached data, and does not present old Codex state as live. | Photo + serial timestamps | NOT RUN |
| HW-202 | Restart the paired Mac host without rebooting the board. | Reconnecting is visible; authenticated online state returns automatically without reprovisioning. | Video + host/serial logs | NOT RUN |
| HW-203 | Disable Wi-Fi after a successful weather result and allow the next refresh attempt to fail. | Cached weather becomes visibly `STALE`; it is not labeled live and attribution remains present. | Before/after photo + log | NOT RUN |
| HW-204 | Boot with no usable weather cache and no network. | Weather shows setup/offline/error guidance without fabricated values or an endless blocking loader. | Photo + log | NOT RUN |
| HW-205 | Supply fixture tasks with very long UTF-8 titles/summaries from the Mac test source. | Text truncates inside its row; no overlap, crash, replacement-character corruption, or changed touch target. | Photo with sanitized fixture text | NOT RUN |
| HW-206 | Enable privacy mode while task summaries exist, navigate away/back, then reboot. | Titles/summaries are hidden everywhere on the panel; counts/coarse state may remain; privacy survives reboot. | Photos before/after + reboot | NOT RUN |
| HW-207 | After time synchronization, compare the header and Pulse screensaver with a trusted local clock across a minute boundary. Repeat after changing the paired Mac timezone, then once with an older/no companion and configured weather. | Time advances once per minute; the current Mac timezone wins while supplied, weather timezone remains the compatibility fallback, the chosen offset survives reboot, and unsynchronized boot never shows a fabricated time. | Timed photo pairs + redacted host/serial logs | NOT RUN |

## D. Screensaver, backlight, and wake safety

| ID | Procedure | Pass condition | Evidence | Result |
| --- | --- | --- | --- | --- |
| HW-301 | Set Pulse screensaver to 2 minutes and leave the board untouched. | Static saver appears at approximately 2 minutes; time/status continue updating and serial remains free of watchdog, panic, or reboot output for at least 5 minutes. | Timed video + serial log | NOT RUN |
| HW-302 | Touch once while only the screensaver is active. | Normal UI returns and the touch does not activate the control underneath it. | Video | NOT RUN |
| HW-303 | Set display off to 5 minutes and leave the board untouched. | CH422G `DISP` makes the physical backlight fully dark at approximately 5 minutes; this is not merely a black framebuffer. | Dark-room video + current observation if available | NOT RUN |
| HW-304 | Touch once while the backlight is off. | Backlight returns; the wake touch is consumed and no hidden control changes. | Video showing unchanged setting/page | NOT RUN |
| HW-305 | Tap **Turn display off now**, wait, wake, then repeat ten times. | 10/10 cycles turn off and recover without a reset, frozen touch controller, or accidental action. | Video + cycle count + serial log | NOT RUN |
| HW-306 | Select `Never` for both timeouts and leave untouched for longer than the former timeout. | Screensaver and backlight remain on; setting is honored after reboot. | Timed notes + photos | NOT RUN |
| HW-307 | Cold-boot ten times while recording the panel and serial output. | No uninitialized or torn frame appears before the first Dashboard frame; the clean one-frame reveal does not animate or stall the 1024×600 software renderer; serial reports first-frame time with no watchdog, panic, or reboot. | Slow-motion video + ten first-frame timings | NOT RUN |

## E. Network and data paths

| ID | Procedure | Pass condition | Evidence | Result |
| --- | --- | --- | --- | --- |
| HW-401 | Boot with the known Wi-Fi and paired Mac already available. | Wi-Fi and authenticated Mac sync recover automatically; no USB step is required after provisioning. | Redacted log + online photo | NOT RUN |
| HW-402 | Reboot the access point, then restore it. | Board stays responsive, shows offline/retrying honestly, and reconnects without reset or reprovisioning. | Timed video + serial log | NOT RUN |
| HW-403 | Reboot the Mac while the board stays powered. | Board remains usable for direct features and authenticated sync returns when the host launches. | Timed notes + board/host logs | NOT RUN |
| HW-404 | Keep the Mac off and reboot the board with working Wi-Fi. | Direct weather synchronizes time, verifies HTTPS, and reaches `LIVE` independently. | Photo + certificate/time/weather log lines | NOT RUN |
| HW-405 | With the Mac companion running, compare one sanitized Codex snapshot with the panel. | Counts/coarse states match; no prompt, transcript, local path, credential, or unbounded private text reaches the board. | Redacted host payload + photo | NOT RUN |
| HW-406 | Change to an unknown Wi-Fi network. | Board gives clear offline/setup guidance and never exposes the stored SSID password on screen or serial output. | Photo + redacted log | NOT RUN |
| HW-407 | Stop the menu companion and run `./tools/host screenshot --output /tmp/ilo-board-live.png`; repeat on all five pages and once during animation. | Each authenticated capture completes without reset or UI freeze; PNG is exactly 1024×600; orientation, red/blue channels, alpha-rendered icon, visible page, and freshness match a simultaneous panel photo; no tearing appears; a second run refuses to overwrite without `--force`. | Five PNG/photo pairs + redacted host/serial timing | NOT RUN |
| HW-408 | Verify X News is absent while Off and when Grok is unavailable. Enable it through the Mac confirmation, refresh once from the companion, and compare the verified host cache with the inserted page; vertically scroll five stories, then swipe horizontally to Weather and back. With both an empty and populated cache, pull below/above the board threshold; repeat from either surface during cooldown/in-flight, then disable and re-enable around an existing cache. | Off/unavailable hides the complete page; enabled inserts it in the right order. The Mac shows current verified cache count/age and fetching/result/cooldown state; Mac and board refresh actions share one in-flight job and cooldown. The empty-state pull gives immediate pull/release feedback, an animated center-card loading state, and a terminal result held for at least eight seconds. At most five bounded stories match category/confidence/source handle; vertical and horizontal gestures do not conflict. Cached data never bypasses Off, and no raw output or credentials appear. | Redacted cache fields + companion/board photos + gesture video + host/serial log | PARTIAL 2026-08-12: physical empty-state pull queued and sent promptly; spinner was visually confirmed. One uninterrupted authenticated Grok run produced five newly cited stories that passed the strict local validator, were cached, securely synced over TLS-PSK, and appeared on the physical 5B. Refined typography firmware was hash-verified, flashed, booted cleanly, restored Wi-Fi, and reconnected securely. Populated-feed vertical scrolling and the final on-panel typography judgment remain pending. |
| HW-409 | Connect the board to a MacBook, then test battery power, charging, optimized/not-charging adapter power, and full charge. Allow up to 30 seconds after each transition. | Dashboard percentage stays within 0–100 and the label changes only among On battery, Charging, Power adapter, and Fully charged. | Four photos plus sanitized host snapshot | NOT RUN |
| HW-410 | Serve a snapshot without `macPower`, then connect from a Mac with no internal battery if available. | Board remains stable and shows Power unavailable; it never retains a previous laptop reading as current. | Photo and serial log | NOT RUN |
| HW-411 | USB-flash signed v0.2.0, confirm the bridge boots as the initial valid slot and Settings/Mac show signed OTA ready, publish a newer signed candidate, request install from each UI, reboot, and observe at least 30 seconds. Repeat the newer candidate with an intentional pre-confirmation reset. | The bridge boots without a loop and restores NVS; download progress reaches verification; a healthy later OTA candidate becomes valid only after the stability window; a failed later candidate automatically returns to the previous UI/settings. | Redacted serial log + before/after photos + slot states | PARTIAL 2026-08-12: signed v0.2.0 bridge was signature-verified and USB-flashed with NVS preserved. Boot log proved v0.2.0 in `ota_0`, exact 5B display/touch initialization, saved Wi-Fi recovery, HTTPS certificate validation, and paired-Mac Bonjour discovery. As expected for `ota_data_initial`, the USB bridge slot was already valid; the 30-second pending gate applies to the first wireless candidate. Settings/Mac visual state and v0.2.1 OTA/rollback remain pending. |
| HW-412 | Serve/publish controlled test manifests for a modified manifest, unsigned image, image signed by an untrusted key, corrupt/truncated image, and cut power during both inactive-slot write and the first-boot health window. | Manifest failures write nothing; every invalid/incomplete image is rejected; write interruption keeps the old slot selected; first-boot interruption rolls back; NVS remains usable; USB recovery remains possible. | Artifact hashes + redacted verifier/serial logs | NOT RUN |
| HW-413 | Install the signed companion on a Mac provisioned only through the CLI. Launch, quit, relaunch, authorize from the in-app secure-pairing card, then quit/relaunch twice and apply one signed Sparkle update. | No system Keychain dialog appears before the explanation or without the explicit button. One **Allow** completes migration; both later launches and the signed update connect without another password prompt. Deny/cancel leaves the service stopped and retryable without deleting either pairing item. | Screen recording with secrets/IDs redacted + connection history | NOT RUN |
| HW-414 | With weather unconfigured, reboot on known Wi-Fi and compare header/Pulse time to the Mac; then stop the companion and reboot again. Finally remove every main-power source for at least ten seconds with the RTC battery switch on, restore power without network access, and compare the retained clock before reconnecting Wi-Fi. | SNTP removes `TIME SYNC NEEDED` independently of weather; the authenticated local UTC offset/zone persists; the battery-backed PCF85063 restores trusted UTC after a true cold boot; network recovery refreshes the RTC without requiring the Mac. | Redacted serial log + timed photos | PARTIAL 2026-08-13: firmware 0.2.7 was hash-verified and USB-flashed, booted cleanly on the physical 5B, joined saved Wi-Fi, synchronized over SNTP, and received a successful PCF85063 UTC write acknowledgement. A USB-triggered reset then booted 0.2.7 cleanly again. True loss-of-main-power retention, RTC-first boot logging, and on-panel/local-zone comparison remain pending. |
| HW-415 | Enable Mac weather location after reading the pre-permission explanation, approve macOS once, then disconnect the Mac and reboot the board. | Companion shows a city/region derived only after rounding to two decimals; Dashboard shows the same bounded label, icon, temperature, condition, and honest LIVE/STALE state; board reaches LIVE weather and continues independently after Mac removal. Disable stops future updates without leaking coordinates in diagnostics/logs. | Permission recording + redacted snapshots + Dashboard/Weather photos | NOT RUN |
| HW-416 | In Settings, open Wi-Fi, enter a second 2.4 GHz WPA2/WPA3 Personal network with the masked keyboard, save, and recover once with USB provisioning. | Password stays masked and absent from logs; board reconnects without Mac/USB; invalid lengths are rejected; USB recovery still works. | Gesture video + redacted network logs | NOT RUN |
| HW-417 | Serve Codex task titles/summaries containing smart quotes, dashes, bullets, accented Latin text, emoji, and unsupported scripts from both the current companion and a legacy fixture. | Dashboard and Codex render readable ASCII fallbacks with no missing-glyph boxes, invalid UTF-8, overlap, or crash; the Mac-side normalization and firmware defense agree. | Sanitized fixture + Dashboard/Codex photos | NOT RUN |
| HW-418 | With the paired board attached, observe the companion USB row; make Wi-Fi unavailable, verify authenticated USB sync, restore Wi-Fi, then unplug/replug USB. Finally stop the service and flash once. | Physical attachment is shown independently; only the paired board authenticates; USB carries the normal bounded sync only while Wi-Fi is unavailable; restored Wi-Fi preempts USB without losing sync; unplug/replug recovers; stopping the service releases the serial port for flashing. | Redacted companion/board video + transport logs | PARTIAL 2026-08-13: the connected 5B was matched through native ESP32-S3 USB Serial/JTAG, the new firmware built and flashed, booted to its first interactive frame without watchdog/reset, started the USB task, and returned a correctly formed fresh-nonce challenge. Swift cryptography tests and the firmware build pass. A signed companion authenticated USB snapshot, live Wi-Fi preemption, unplug/replug, and release-for-flash sequence remain pending. |
| HW-414 | From a fresh signed install in `/Applications`, enable **Launch at login**, review Login Items if requested, then log out/in or reboot. Repeat after one signed Sparkle update, then disable it and log out/in again. | First-time `.notFound` is shown as Off with an Enable action; registration becomes On or honestly requests approval. The signed app launches once after login and keeps working after update; disabling prevents the next automatic launch. | Redacted screen recording + Background Items state + process path | NOT RUN |

## F. Endurance and release decision

| ID | Procedure | Pass condition | Evidence | Result |
| --- | --- | --- | --- | --- |
| HW-501 | Run the board for at least 8 hours with Mac sync and weather enabled; interact once per hour. | No reset/panic, UI freeze, progressive memory failure, auth storm, or unusable touch latency. | Full serial log + hourly notes | NOT RUN |
| HW-502 | During endurance, stop/start Wi-Fi and the host at least three times each. | All six recoveries complete without USB intervention or leaked private data in logs. | Timestamped recovery table | NOT RUN |
| HW-503 | Run `make verify` again from the unchanged commit after the physical session. | Hardware-independent suite and firmware build still pass. | Command output | NOT RUN |
| HW-504 | Review every failed/not-run item and the evidence folder. | Release is blocked by any safety, privacy, boot, touch, backlight, or recovery failure; deferrals are explicit. | Signed result record | NOT RUN |

## Deferred gates

Framebuffer screenshot transport is implemented and hardware-independently verified, but HW-407 remains its physical fidelity/reliability release gate; panel photos are still authoritative until it passes. The board-owned signed HTTPS updater, Settings/Mac controls, dual-slot rollback, and release-only profile are compile-verified. Production delivery remains gated on HW-411/HW-412, durable key custody, signed v0.2.0 USB bridge installation, and recovery evidence. Until those pass, USB flash remains the supported firmware update path.

Board-originated Codex approvals are also deferred. The current approval-request fixture is intentionally disconnected and must continue to display **NO ACTION SENT**. A future physical gate must prove authoritative live request state, exact consequence, expiry, hold duration, a separate confirmation, one-time/replay rejection, cancellation, disconnect behavior, and Mac-side audit evidence before remote actions can be enabled.
