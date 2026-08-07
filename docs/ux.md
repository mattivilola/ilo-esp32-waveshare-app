# Touch UI direction

The first screen is a compact operations console for one person watching several Codex tasks from arm's length.

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

## Layout

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

The signature is the vertical “work pulse”: one continuous status rail that makes the system's overall state readable before individual cards. Amber is reserved for genuine attention, not decoration.

Touch targets are at least 48×48 logical pixels. Empty, sleeping, reconnecting, and stale-data states explain what is happening and what the user can do. Phase 1 offers inspection only; it never draws a control that cannot safely complete its action.

## macOS menu-bar companion

The Mac companion uses a SwiftUI `MenuBarExtra` with window-style content and intentionally stays out of the Dock during this development phase. Its 360-point dashboard mirrors the board's status hierarchy without copying the fixed dark palette: it uses native macOS material, semantic text colors, and state tints so Light and Dark appearances both remain legible.

The compact surface shows:

- one clear connection-state chip;
- board model and shortened opaque identity;
- listening port and most recent successful sync;
- the active security/capability boundary (`TLS 1.2 · Read only`);
- start/stop service, copy identity, and quit actions.

Green is reserved for an authenticated board connection, orange means the service is ready but waiting, red means action is required, and neutral means stopped or not provisioned. Longer diagnostics stay in the status card rather than expanding menu labels.
