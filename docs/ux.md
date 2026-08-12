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

The signature is the vertical “work pulse”: one continuous status rail that makes the system's overall state readable before individual cards. Amber is reserved for genuine attention, not decoration. Dashboard is the default wake screen and should answer three questions in under two seconds: is everything connected, does anything need me, and what is moving now? Each recent Codex row is a direct target: one tap opens the Codex page with that exact related chat already selected. The former local focus-timer strip now shows the newest verified X News headline and opens X News; when that feed is unavailable, it falls back to live Codex task counts and opens Codex.

On cold boot, the backlight stays off until the first real Dashboard frame is rendered. A sub-half-second “ILO beacon” then appears over the live Dashboard: two signal rings expand from the centered roundel, one scan line crosses the display, and the left work-pulse rail briefly flares. Connection and data startup continue normally underneath. The animation never acts as a splash-screen gate: the Dashboard is already present and touch can finish the effect immediately.

## Codex

Codex shows sanitized task names, coarse state, last update, and attention type. It also keeps the capability boundary visible: history from a separately launched App Server is not presented as authoritative live Desktop state. Full prompts, transcripts, paths, commands, diffs, and credentials do not belong on the board.

The fixed continue action is deliberately distinct from approval: tapping a task shows the exact `Please continue.` consequence, holding only arms it, and a separate tap confirms it. “Approval needed” never implies that the board can approve. Any future approval design still requires explicit action text, origin, consequence, expiry, hold-to-confirm, and a Mac-side audit trail.

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

The first implementation is “Pulse”: a slow-moving ILO roundel and one small connection indicator on an otherwise black screen. Touch wakes immediately. When waking from backlight-off sleep, the firmware consumes the entire first touch until release so it cannot accidentally activate a control underneath.

This IPS LCD is not primarily at risk of OLED burn-in. A moving screensaver is therefore an ambient experience. The exact 5B routes `DISP` through a CH422G expander output and does not expose PWM brightness control, so the honest power policy is:

1. backlight on during interaction;
2. moving Pulse screen after the configured idle timeout;
3. backlight fully off after the display-off timeout;
4. consume the first touch, restore the backlight, and return to the previous page.

## Work-pulse extensions

Useful future signals should earn dashboard space by being actionable and quickly understood:

- next calendar event and focus block;
- build/deploy/CI state for the active project;
- production incident or uptime alert;
- priority Slack/Teams mentions, summarized by the Mac;
- GitHub review/PR attention;
- Mac thermal pressure and do-not-disturb state. Battery percentage and charging state are now implemented as a bounded read-only Work Pulse signal;
- a focus timer and one selected “next action.”

The dashboard should aggregate only the top one or two of these. Dedicated pages or a later configurable card stack are better than turning the first screen into a wall of metrics.

## Desktop prototype

`BoardUIPrototype` is a SwiftUI representation fixed at the board's exact 1024×600 resolution. It exists for rapid layout review, deterministic documentation screenshots, and interaction design while hardware is unavailable. It is not a replacement for LVGL or physical verification.

The preview uses the same Carbon/Slate/Steel/Signal/Amber/Mist/Fog system, real ILO roundel, page order, content density, and touch-sized navigation intended for firmware. `make ui-preview` opens it; `make ui-screenshots` exports all pages.

The first LVGL port now mirrors the adaptive four/five-page structure with `lv_tileview`, dynamically sized bottom navigation, the generated 48×48 ARGB roundel, model-bound Dashboard/Codex task rows, optional verified cached X News, sample Weather, persistent NVS-backed Settings, summary privacy, a moving Pulse screensaver, and binary backlight sleep. X News accepts vertical momentum scrolling for up to five stories and chains horizontal gestures back to the page tileview; a hint appears only when more than three stories are available. The X News page never runs Grok or receives Grok prompts, reasoning, authentication, or raw output; the Mac companion sends only the bounded feed that passed host-side validation. It has passed firmware compilation only. Physical review must precede any claim that the prototype and LVGL output match.

## macOS menu-bar companion

The Mac companion uses a SwiftUI `MenuBarExtra` with window-style content and intentionally stays out of the Dock during this development phase. Its compact 420×540-point dashboard mirrors the board's status hierarchy without copying the fixed dark palette: it uses native macOS material, semantic text colors, and state tints so Light and Dark appearances both remain legible. Overview keeps connection health, device facts, and quick controls visible; Features contains the complete firmware and opt-in controls; Activity keeps the bounded connection log available without making the default panel taller.

The compact surface shows:

- one clear connection-state chip;
- board model and shortened opaque identity;
- listening port and most recent successful sync;
- the active security/capability boundary (`TLS 1.2 · Read only`);
- start/stop service, copy identity, and quit actions.

Green is reserved for an authenticated board connection, orange means the service is ready but waiting, red means action is required, and neutral means stopped or not provisioned. Longer diagnostics stay in the status card rather than expanding menu labels.
