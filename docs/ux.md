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

The device uses four horizontally ordered pages:

1. Dashboard
2. Codex
3. Weather
4. Settings

A horizontal swipe moves one page at a time. The bottom navigation is always visible so the gesture is discoverable and every screen remains one tap away. Page changes must not wrap from Settings to Dashboard because accidental edge swipes should be predictable.

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

The signature is the vertical “work pulse”: one continuous status rail that makes the system's overall state readable before individual cards. Amber is reserved for genuine attention, not decoration. Dashboard is the default wake screen and should answer three questions in under two seconds: is everything connected, does anything need me, and what is moving now?

## Codex

Codex shows sanitized task names, coarse state, last update, and attention type. It also keeps the capability boundary visible: history from a separately launched App Server is not presented as authoritative live Desktop state. Full prompts, transcripts, paths, commands, diffs, and credentials do not belong on the board.

When actions are introduced later, “approval needed” must never imply that the board has already been authorized to approve it. A separate design will require explicit action text, origin, consequence, expiry, hold-to-confirm, and a Mac-side audit trail.

## Weather

Weather can operate independently of the Mac after direct HTTPS, clock synchronization, caching, and location configuration are complete. Sample data is always labeled. Live data needs generated-at time and a stale/offline state; silently showing old weather as current is not acceptable.

The board optimizes for the next few hours and today rather than dense meteorological detail. Current temperature, condition, precipitation transition, wind, and three compact daily summaries fit the glance use case.

## Settings

The first device-manageable preferences are:

- brightness;
- idle dim timeout;
- screen-off timeout;
- screensaver mode;
- Celsius/Fahrenheit and 12/24-hour display;
- weather location and refresh state;
- whether task summaries are visible in privacy mode;
- connection diagnostics and a manual reconnect;
- firmware/version/update status.

Reboot, pairing reset, erase, and update installation require a separate confirmation surface. Wi-Fi SSID/password entry remains in the secure USB/macOS flow initially; a five-inch touch keyboard is poor credential UX and easier to shoulder-surf.

## Screensaver and power

The default concept is “Pulse clock”: a slow-moving ILO roundel, large time, and one small connection/attention indicator on an otherwise black screen. Touch wakes immediately. New genuine attention may wake to a dim attention summary, subject to quiet-hours settings.

This IPS LCD is not primarily at risk of OLED burn-in. A moving screensaver is therefore an ambient experience, while the backlight policy delivers power savings:

1. normal brightness during interaction;
2. dim after the idle timeout;
3. screensaver at a low backlight level;
4. backlight off after the screen-off timeout.

## Work-pulse extensions

Useful future signals should earn dashboard space by being actionable and quickly understood:

- next calendar event and focus block;
- build/deploy/CI state for the active project;
- production incident or uptime alert;
- priority Slack/Teams mentions, summarized by the Mac;
- GitHub review/PR attention;
- Mac battery, charging, thermal pressure, and do-not-disturb state;
- a focus timer and one selected “next action.”

The dashboard should aggregate only the top one or two of these. Dedicated pages or a later configurable card stack are better than turning the first screen into a wall of metrics.

## Desktop prototype

`BoardUIPrototype` is a SwiftUI representation fixed at the board's exact 1024×600 resolution. It exists for rapid layout review, deterministic documentation screenshots, and interaction design while hardware is unavailable. It is not a replacement for LVGL or physical verification.

The preview uses the same Carbon/Slate/Steel/Signal/Amber/Mist/Fog system, real ILO roundel, page order, content density, and touch-sized navigation intended for firmware. `make ui-preview` opens it; `make ui-screenshots` exports all pages.

The first LVGL port now mirrors the four-page structure with `lv_tileview`, fixed bottom navigation, the generated 48×48 ARGB roundel, model-bound Dashboard/Codex task rows, sample Weather, non-destructive Settings status, and a two-minute Pulse screensaver. It has passed firmware compilation only. Physical review must precede any claim that the prototype and LVGL output match.

## macOS menu-bar companion

The Mac companion uses a SwiftUI `MenuBarExtra` with window-style content and intentionally stays out of the Dock during this development phase. Its 360-point dashboard mirrors the board's status hierarchy without copying the fixed dark palette: it uses native macOS material, semantic text colors, and state tints so Light and Dark appearances both remain legible.

The compact surface shows:

- one clear connection-state chip;
- board model and shortened opaque identity;
- listening port and most recent successful sync;
- the active security/capability boundary (`TLS 1.2 · Read only`);
- start/stop service, copy identity, and quit actions.

Green is reserved for an authenticated board connection, orange means the service is ready but waiting, red means action is required, and neutral means stopped or not provisioned. Longer diagnostics stay in the status card rather than expanding menu labels.
