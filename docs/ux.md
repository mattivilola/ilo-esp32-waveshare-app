# Touch UI direction

The first screen is a compact operations console for one person watching several Codex tasks from arm's length.

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

