# Touch UI direction

ILO Board is a compact personal operations console for one person watching work, decisions, weather, and device health from arm's length.

The layout is designed for the 1024×600 panel on the Waveshare ESP32-S3-Touch-LCD-5B (SKU 28151). It is not a scaled 800×480 layout.

## Visual tokens

- Carbon `#0A0F14` — canvas
- Slate `#131B22` — task surfaces
- Steel `#24313C` — structure and inactive states
- Signal `#65E5B8` — healthy activity
- Amber `#FFB55A` — attention required
- Mist `#F3F7F8` — primary text
- Fog `#8EA2B2` — secondary text

LVGL's Montserrat assets provide a restrained three-role scale for Phase 1: 28 px display, 20 px body, and 14 px utility. A later font asset pass can add a more distinctive data face without coupling it to layout code.

## Navigation

The device uses four horizontally ordered pages by default:

1. Dashboard
2. Codex
3. Weather
4. Settings

When X News is explicitly enabled on a Mac with Grok available, it is inserted between Codex and Weather as a fifth page. Disabling it, or losing Grok availability, removes the complete page and expands the remaining navigation targets. A horizontal swipe moves one page at a time. The bottom navigation is always visible so the gesture is discoverable and every screen remains one tap away. Page changes must not wrap from Settings to Dashboard because accidental edge swipes should be predictable.

Touch targets are at least 48×48 logical pixels. Empty, sleeping, reconnecting, and stale-data states explain what is happening and what the user can do. Phase 1 offers inspection only; it never draws a control that cannot safely complete its action.

## Dashboard

```text
┌──────────────────────────────────────────────────────────────────┐
│ ILO / WORK PULSE                         Mac online  •  23:41     │
├───────────────┬──────────────────────────────────────────────────┤
│ attention     │ active work                                      │
│      1        │ ● Board foundation     Building firmware          │
│               │ ● Mac service          Running tests              │
│ review on Mac │ ○ Weather feed         Not configured             │
├───────────────┴──────────────────────────────────────────────────┤
│ Last update 4s ago                     swipe to inspect           │
└──────────────────────────────────────────────────────────────────┘
```

The signature is the vertical “work pulse”: one continuous status rail that makes the system's overall state readable before individual cards. Amber is reserved for genuine attention, not decoration. Dashboard is the default wake screen and should answer three questions in under two seconds: is everything connected, does anything need me, and what is moving now? Each recent Codex row is a direct target: one tap opens the Codex page with that exact related chat already selected. The former local focus-timer strip now shows the newest X News headline and opens X News; when that feed is unavailable, it falls back to live Codex task counts and opens Codex.

On cold boot, the backlight stays off until the first real Dashboard frame is rendered. A sub-half-second “ILO beacon” then appears over the live Dashboard: two signal rings expand from the centered roundel, one scan line crosses the display, and the left work-pulse rail briefly flares. Connection and data startup continue normally underneath. The animation never acts as a splash-screen gate: the Dashboard is already present and touch can finish the effect immediately.

## Codex

Codex shows the ten most recent sanitized tasks in a vertically scrollable list. The first tap only selects a task and loads its bounded detail into the right panel; Open Chat is a separate local action. The focused reader keeps the newest six user/Codex text messages simple and vertically scrollable while a narrow right card shows coarse state, last update, visible message count, and available fixed actions. It opens at the newest message and stays visibly labeled `READ ONLY` and `RECENT`; Back returns to the task/action surface. Commands, tool output, reasoning, paths, diffs, attachments, approval payloads, credentials, and the complete transcript do not belong on the board. Enabling the board's summary privacy setting suppresses the chat request as well as the list summaries.

Fixed actions remain distinct from reading the conversation. The right panel reserves Open Chat plus up to two remote slots: Continue for an eligible idle task, or Approve/Reject when the newest completed turn contains a Plan-mode plan. Holding only arms the chosen action and a separate tap confirms it. Approve means implement that re-fetched plan in default mode; Reject means return to Plan mode with a fixed revision request. Neither action can approve shell/file permissions, answer a question, alter the fixed text, or steer an active turn.

## Focus Cockpit

Focus opens as a full-screen mode above the normal page chrome. Tap the Settings duration to cycle 25/45/60 minutes and hold it to start an open session; holding a recent Codex row starts the same timer with that row's visible title attached for the current run. A large native LVGL arc, monospaced countdown, and explicit `RTC BACKED`/`PAUSED` state remain readable at a glance. Controls are bounded to Pause/Resume, +5 minutes, and hold-to-end. Natural completion is explicit and dismissible; ending early does not claim completion or notify the Mac.

The ring updates once per second without transforms, shadows, or continuous animation. The absolute deadline and pause state survive reset in NVS and use the battery-backed UTC clock, while attached task text remains memory-only. The optional Mac notification receives no title or task identifier.

## Weather

Weather operates independently of the Mac after USB provisioning supplies a name and coordinates. The board synchronizes time before a certificate-verified HTTPS request, refreshes every 30 minutes, and distinguishes LIVE, STALE, OFFLINE, and SETUP NEEDED. Desktop preview data is labeled PREVIEW DATA; live firmware never silently presents an old result as current. The provider attribution remains visible on the Weather page.

The board optimizes for the next few hours and today rather than dense meteorological detail. The Dashboard now carries a compact city, current temperature, condition icon, and honest `LIVE`/`STALE`/`UPDATING` state; the full Weather page keeps precipitation transition, wind, and three compact daily summaries.

## Settings

The first device-manageable preferences are:

- Pulse screensaver timeout (`Never`, 2, or 5 minutes);
- binary display-off timeout (`Never`, 5, 10, or 30 minutes) and “off now”;
- task-summary visibility on the board;
- Celsius/Fahrenheit and 12/24-hour display;
- weather location and refresh state;
- whether task summaries are visible in privacy mode;
- connection diagnostics and a manual reconnect;
- firmware/version/update status.

Settings reports whether X News is Mac-enabled, but cannot grant Grok consent or change its paid-tool schedule.

Reboot, pairing reset, erase, and update installation require a separate confirmation surface. Wi-Fi can be changed locally from Settings with a masked touch keyboard; the flow clearly warns about shoulder-surfing, validates WPA2/WPA3 Personal credential lengths, and retains USB provisioning as the recovery route.

## Screensaver and power

The screensaver is “Pulse”: the clock/roundel cluster occupies the left two-thirds and snaps among five bounded positions every 20 seconds. The right third is a medium slate-gray ILO PET panel where Lando breathes, blinks, and occasionally waves using native-size RGB565 frame swaps. The panel color keeps his mostly black fur distinct and is generated from one configurable color value. Tap its Settings row to cycle the timeout; hold it for 0.9 seconds to show the saver immediately without changing the saved value. Touch wakes immediately. When waking from backlight-off sleep, the firmware consumes the entire first touch until release so it cannot accidentally activate a control underneath.

This IPS LCD is not primarily at risk of OLED burn-in. A moving screensaver is therefore an ambient experience. The exact 5B routes `DISP` through a CH422G expander output and does not expose PWM brightness control, so the honest power policy is:

1. backlight on during interaction;
2. bounded Pulse/Lando screen after the configured idle timeout;
3. backlight fully off after the display-off timeout;
4. consume the first touch, restore the backlight, and return to the previous page.

## Work-pulse extensions

Useful future signals should earn dashboard space by being actionable and quickly understood:

- next calendar event;
- build/deploy/CI state for the active project;
- production incident or uptime alert;
- priority Slack/Teams mentions, summarized by the Mac;
- GitHub review/PR attention;
- Mac thermal pressure and do-not-disturb state. Battery percentage and charging state are now implemented as a bounded read-only Work Pulse signal;

The dashboard should aggregate only the top one or two of these. Dedicated pages or a later configurable card stack are better than turning the first screen into a wall of metrics.

## Desktop prototype

`BoardUIPrototype` is a SwiftUI representation fixed at the board's exact 1024×600 resolution. It exists for rapid layout review, deterministic documentation screenshots, and interaction design while hardware is unavailable. It is not a replacement for LVGL or physical verification.

The preview uses the same Carbon/Slate/Steel/Signal/Amber/Mist/Fog system, real ILO roundel, page order, content density, and touch-sized navigation intended for firmware. `make ui-preview` opens it; `make ui-screenshots` exports all pages; `./tools/board ui-screenshot --screen codex --chat` renders the focused chat-reader fixture; `swift run --package-path mac-service ilo-board-preview focus-screenshot` renders the Focus Cockpit.

The first LVGL port now mirrors the adaptive four/five-page structure with `lv_tileview`, dynamically sized bottom navigation, the generated 48×48 ARGB roundel, model-bound Dashboard/Codex task rows, optional bounded X News, sample Weather, persistent NVS-backed Settings, summary privacy, a bounded Pulse/Lando screensaver, and binary backlight sleep. Lando uses ten precomposited RGB565 frames (six idle and four waving), never a scaled or alpha-blended atlas; his animation pauses whenever the saver is hidden or the backlight is off. X News accepts vertical momentum scrolling for up to fifteen stories and chains horizontal gestures back to the page tileview; every row exposes category/confidence chips and opens a full-width, vertically scrollable post-detail view with Back, author, timestamp, summary, available post text, and direct URL. A feed hint appears only when more than three stories are available. The X News page never runs Grok or receives Grok prompts, reasoning, authentication, or raw output; the Mac companion sends only the bounded feed that passed host-side structural validation. Physical review must precede any claim that the prototype and LVGL output match.

## macOS menu-bar companion

The Mac companion uses a SwiftUI `MenuBarExtra` with window-style content and intentionally stays out of the Dock during this development phase. Its compact 420×580-point dashboard mirrors the board's status hierarchy without copying the fixed dark palette: it uses native macOS material, semantic text colors, and state tints so Light and Dark appearances both remain legible. Overview keeps connection health, device facts, and quick controls visible; Features contains the complete firmware and opt-in controls; Activity keeps the bounded connection log available without making the default panel taller.

The compact surface shows:

- one clear connection-state chip;
- board model and shortened opaque identity;
- listening port, independent USB attachment state, and most recent successful sync;
- the active transport and security/capability boundary (`TLS 1.2` over Wi-Fi or `ChaCha20-Poly1305` over paired USB);
- start/stop service, copy identity, and quit actions.

Weather location never leaves the companion on an unbounded “Locating…” state. The menu refreshes macOS authorization whenever it opens, distinguishes permission-needed and permission-denied states, links directly to Location Services when access is off or macOS does not answer, and changes an unanswered location request to a retryable unavailable state after 20 seconds.

Green is reserved for an authenticated board connection, orange means the service is ready but waiting, red means action is required, and neutral means stopped or not provisioned. USB attachment alone does not turn the service green: the connected device must complete paired authentication. The status detail names Wi-Fi or USB when sync is active, while the separate USB row continues to show physical attachment. Longer diagnostics stay in the status card rather than expanding menu labels.
