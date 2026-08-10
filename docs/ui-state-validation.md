# Deterministic UI state validation

The state gallery exercises the fixed **1024×600** product layout without hardware. It covers the non-happy paths most likely to cause ambiguous status, clipping, privacy leaks, or unsafe touch behavior later on the Waveshare 5B.

Generate every fixture with:

```bash
swift run --package-path mac-service ilo-board-preview scenario-screenshots
```

Generate one fixture with:

```bash
swift run --package-path mac-service ilo-board-preview \
  scenario-screenshot --scenario long-text --output /tmp/ilo-long-text.png
```

Supported scenario names are `offline`, `loading`, `stale`, `error`, `long-text`, `privacy`, `sleep`, and `reconnect`. Default output is ignored under `artifacts/ui-states/`; the reviewed reference gallery is committed under `docs/images/ui-states/`.

The fixture model is intentionally disconnected from the live transport. It cannot claim that Wi-Fi, TLS, Codex, CH422G backlight control, or touch works. It proves only that each intended state has a deterministic label, page assignment, information hierarchy, and 1024×600 render.

| Scenario | Page | Required UX property |
| --- | --- | --- |
| Offline | Dashboard | Old Mac data is labeled cached/stale; direct weather remains conceptually independent. |
| Loading | Codex | Work is bounded and descriptive; there is no indefinite blank surface or fake live task. |
| Stale | Weather | Last-known values carry a visible age/state and attribution. |
| Error | Weather | No fabricated measurement; recovery guidance and automatic retry are explicit. |
| Long text | Codex | Private-safe fixture text truncates within one-line row geometry. |
| Privacy | Dashboard | Summaries are hidden while coarse state remains useful. |
| Sleep | Dashboard | The deterministic output is completely black; only hardware can prove the backlight is electrically off. |
| Reconnect | Dashboard | Wi-Fi, authenticated Mac session, and cached board data are distinguished. |

<p align="center">
  <img src="images/ui-states/offline.png" alt="Offline dashboard validation fixture" width="49%">
  <img src="images/ui-states/loading.png" alt="Codex loading validation fixture" width="49%">
</p>
<p align="center">
  <img src="images/ui-states/stale.png" alt="Stale weather validation fixture" width="49%">
  <img src="images/ui-states/error.png" alt="Weather error validation fixture" width="49%">
</p>
<p align="center">
  <img src="images/ui-states/long-text.png" alt="Long Codex text validation fixture" width="49%">
  <img src="images/ui-states/privacy.png" alt="Privacy mode validation fixture" width="49%">
</p>
<p align="center">
  <img src="images/ui-states/reconnect.png" alt="Mac reconnect validation fixture" width="49%">
  <img src="images/ui-states/sleep.png" alt="Black simulated display-asleep fixture" width="49%">
</p>

## Review procedure

1. Run the focused Swift tests and regenerate the gallery.
2. Confirm every PNG is exactly 1024×600.
3. Review every label for truthfulness: live, stale, offline, cached, retrying, and private must not be interchangeable.
4. Inspect long text at 100% scale; title and detail must not overlap the badge or change row height.
5. Confirm provider attribution remains visible in both Weather failure fixtures.
6. Treat the black sleep PNG only as a desired visible result. Complete HW-303 through HW-305 in [the physical checklist](hardware-validation.md) before claiming display power/wake behavior.
7. Compare the same states on LVGL during the next hardware session. Exact typography is not required, but hierarchy, truncation, status semantics, and touch geometry are.

The Python gallery test validates the complete filename set, PNG signatures, and dimensions. It intentionally does not pin byte hashes because OS font rasterization can change without changing layout semantics.
