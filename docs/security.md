# Security model

This model covers the firmware built for the Waveshare ESP32-S3-Touch-LCD-5B (SKU 28151) and its paired macOS user service.

## Phase-1 capability

Codex task data and Mac-control capabilities are bounded: `tasks.read`, on-demand `tasks.chat.read`, `macPower.read`, plus an explicitly requested diagnostic display capture. One narrow `tasks.continue.fixed` action can resume an eligible idle/unloaded task with exactly `Please continue.` after hold-to-arm and a separate confirmation. The host sends a normalized task ID, short title, coarse status, attention kind, timestamp, short summary, and optional Mac battery percentage/state. Mac power data excludes the computer name, battery serial, hardware identifiers, health/capacity history, adapter details, and time estimates. Capture returns only the pixels already visible on the paired physical display. The separate `xNews.refresh.request` capability can start only the already-opted-in bounded news adapter; all other mutating requests fail closed.

## Codex privacy boundary

Codex display is optional. With no configured Mac, firmware starts with Codex disabled, exposes no task page or task-backed Dashboard controls, and retains Dashboard, direct Weather, and Settings. A snapshot that explicitly disables Codex carries no task records or task capabilities. Older companions remain compatible because firmware infers Codex visibility only from their existing authenticated `tasks.read` capability.

The host obtains recent task metadata through a local Codex App Server `thread/list` request. Its list decoder accepts only `id`, optional `name`, `updatedAt`, and `status`; prompt previews, working-directory paths, source metadata, Git information, file contents, environment variables, and credentials are ignored.

Opening a visible task can make one on-demand `thread/turns/list` request for at most four recent turns. A separate narrow decoder keeps only the newest six `userMessage` and `agentMessage` text items, sanitizes each to 360 board-safe characters, and drops commands, command output, tools, reasoning, plans, diffs, paths, attachments, approvals, and all unrecognized items. This recent-chat excerpt is read-only, is not included in recurring snapshots, and is not requested when the board's summary privacy setting is enabled. The board labels the surface `READ ONLY`, `RECENT`, and directs the user to the Mac for the complete thread.

Results are capped at six tasks and cached for 15 seconds. The companion owns one App Server child for its lifetime so a confirmed fixed continuation can resume a selected task; it never reads or writes Codex SQLite databases, session logs, or internal state files directly.

A task reported as `notLoaded` is presented as recent history with live Desktop status unavailable. It is not presented as active, waiting for approval, or waiting for an answer. This prevents the separate companion process from overstating what it can observe.

## Pairing and transport

The pairing flow creates an opaque board ID and random 32-byte PSK while USB is physically connected. The host stores the PSK in the user Keychain; the board stores it in NVS. Because CLI provisioning and the Developer ID app are distinct signed clients, the app never reads the CLI-owned item silently at startup. It first presents a bounded explanation and requires an explicit button press; only then can the macOS password dialog appear. After that authorized read, the app writes an app-owned Keychain copy for its stable bundle/signing identity, so later launches and signed updates do not repeatedly prompt. The CLI-owned item remains in Keychain for headless and diagnostic commands. Neither copy is exported, logged, placed in preferences, or written to the repository.

Bonjour TXT advertises only protocol compatibility (`v=1`, `transport=tls-psk-tcp`), not the board ID or secret. The service instance contains only the final eight characters already used in its nonsecret display name; firmware uses it to avoid unrelated compatible hosts, then relies on TLS-PSK and the protocol hello for authoritative pairing identity. Failed or blocked discovery falls back to the provisioned endpoint without weakening authentication.

USB presence is not authentication. The companion may identify the provisioned ESP32-S3 by its recorded USB Serial/JTAG serial number, but it sends no application data until a fresh HMAC-SHA256 challenge/response proves both peers possess the board PSK and the returned board ID matches. HKDF-SHA256 derives a fresh session key from both random nonces. Every subsequent frame is ChaCha20-Poly1305 protected with authenticated direction and a strictly increasing sequence; tag failure, replay, reordering, wrong direction, malformed or oversized input, timeout, or disconnect fails closed. Wi-Fi remains primary and preempts USB. Neither nonces, USB metadata, nor encrypted serial traffic reveal or log the PSK, and no unauthenticated serial command surface is introduced.

`./tools/board provision` reads the Wi-Fi password without terminal echo and sends the key material to the host CLI through standard input, never through process arguments. Its NVS CSV and binary exist only in a permission-restricted temporary directory for the duration of the verified partition write. The persistent host metadata file contains only the nonsecret board ID, protocol version, and service port.

TLS 1.2 PSK protects the local-network link. ChaCha20-Poly1305 protects the authenticated USB fallback after its HMAC/HKDF handshake. Both carry the same bounded application protocol and capabilities; USB does not widen the command surface.

Live framebuffer capture has no unauthenticated HTTP or discovery endpoint. The request is accepted only inside an established paired TLS session after the version-1 hello/subscription exchange. Firmware accepts a bounded request ID and exactly one format/size, copies the framebuffer into temporary PSRAM, sends fixed-size sequenced chunks, attaches a SHA-256 result, then frees the copy. The Mac rejects unsolicited, mismatched, duplicate, reordered, truncated, oversized, or corrupt capture data and refuses to overwrite an output path unless the operator passes `--force`.

OTA is disabled in normal developer builds and enabled only by the signed release profile. The board fetches one compiled HTTPS manifest URL with the ESP certificate bundle, verifies an embedded RSA-3072 public key and exact signed payload bytes, and accepts only the immutable project GCS prefix and exact 5B target. It checks release sequence, semantic versions, byte size and SHA-256 while writing only the inactive slot; `esp_ota_end` verifies the application signature before boot selection changes. A pending image is not marked valid until core display/UI and worker initialization complete and a 30-second no-restart stability window passes. The companion sends only fixed `check` or `install` actions and cannot inject update metadata. No private signing key or upload credential is stored in the project or device. Hardware Secure Boot, flash encryption, anti-rollback eFuses, durable key custody, and the first-device physical fault tests remain explicit production gates.

Direct weather is the only current board-originated Internet request. It sends configured latitude/longitude and ordinary HTTP metadata to `api.open-meteo.com`; it sends no board ID, pairing secret, Wi-Fi password, Codex data, or Mac data. The response is bounded to 8 KiB and HTTPS uses ESP-IDF's CA certificate bundle after SNTP clock synchronization. Weather is optional public-data access, not a general proxy or arbitrary URL feature.

Mac location sharing is off by default. The signed companion first explains the data flow, then requests macOS location permission only after an explicit action. It rounds latitude and longitude to two decimals before asking macOS reverse geocoding (an Apple-provided service that may make a network request) for a bounded city/region label. Only that label and the rounded point enter the authenticated board snapshot; no precise location history is retained. Because city lookup expands the original coordinate-only flow, the companion uses a new consent version and does not silently reuse the previous choice. Firmware validates the bounds, stores the coarse location and display label in NVS, and uses them only for direct Open-Meteo requests and the board's weather UI. Disabling sharing stops future Mac updates; clearing an already stored board location remains an explicit board/USB reset action so standalone weather does not disappear unexpectedly.

The on-board Wi-Fi editor masks password input and writes credentials directly to board NVS. Wi-Fi passwords are not included in companion snapshots, Bonjour records, screenshots, or serial logs. USB provisioning remains the recovery path if touch entry or the selected network fails.

The authenticated companion snapshot may include only the Mac's current bounded UTC offset and timezone abbreviation for local clock display. It does not transmit the IANA timezone identifier, locale, location, system clock history, or other regional settings. The board obtains absolute time independently through SNTP.

Optional X News remains Mac-mediated and disabled by default. Enabling it requires either explicit CLI consent or the companion’s confirmation dialog because the authenticated Grok process uses `--yolo` for X search and may consume paid capacity. Missing Grok or an Off schedule sends a false visibility flag and hides the complete board page; the ESP32 cannot enable it. The process runs from an isolated temporary directory with memory/subagents disabled, a three-minute deadline, eight-turn limit, and a 1 MB output cap. The adapter does one focused X search without an independent claim-verification pass. Output is still rejected unless bounded stories contain matching direct X status URLs whose Snowflake timestamps fall inside the requested 24-hour window. Invalid output never replaces the previous cache. Only the visibility flag and bounded feed—headline, summary, available post text, category, confidence, author, timestamp, and direct URL—cross TLS to the board; Grok/X credentials, reasoning, sessions, prompts, usage, stderr, and raw output stay off the wire.

Pull-to-refresh is a narrow authenticated request, not a general command channel. It is accepted only after TLS hello/subscription, carries a random bounded request ID and no prompt, and cannot enable Grok consent. The Mac independently enforces opt-in, a 15-minute cost cooldown, one process at a time, the same three-minute timeout/validator, and last-good-cache preservation. The board receives only one of six coarse result states and never sees raw process errors.

Codex continuation is also a narrow authenticated request, not a general prompt channel. It is off by default and requires explicit opt-in in the Mac companion, where it can be revoked immediately. The board sends only a random one-time request ID, a currently displayed task ID, and the fixed `continue` action token. The Mac rechecks consent, rejects malformed or recently replayed IDs, re-lists current tasks, and accepts only idle or unloaded tasks among the six visible records. It then uses the supported App Server to resume the task and constructs exactly `Please continue.` locally. The board cannot choose or alter that text. Active tasks, attention requests, failures, and stale/unknown IDs fail closed.

The Mac companion update channel is separate from firmware OTA. Public releases are Developer-ID signed, notarized, stapled, and additionally signed with Sparkle EdDSA. The private update key remains in the login Keychain; only its public key is embedded in the app. The HTTPS appcast contains bounded changelog text and an immutable versioned GCS URL. Distribution validates the stapled DMG and byte-identical latest alias before signing, then uploads the appcast last. A compromised public bucket cannot produce an accepted replacement DMG without the Apple and EdDSA signing identities.

Ad-hoc `make app` builds use `disable-library-validation` only so a Team-ID-less development executable can load the prebuilt Sparkle framework. `sign_release.sh` never applies that entitlement: Developer ID releases explicitly re-sign Sparkle's nested helpers/framework and the app with the same Apple identity before notarization.

## Explicit exclusions

The device cannot currently:

- approve commands or file changes;
- grant additional permissions;
- use `acceptForSession` or policy amendments;
- answer free-form or structured Codex questions;
- steer or interrupt active Codex turns, or start turns with anything except the fixed eligible-task continuation;
- run shell commands or AppleScript;
- read or write Codex SQLite/session files directly.

Later decision support requires one-time request IDs, expiry, replay protection, current-state validation, complete action context, an audit trail, and a visible Mac-side revocation control. File-change approval remains Mac-only unless a device can present enough of the diff for informed consent.

## Development caveats

- ESP NVS is not resistant to physical extraction until NVS/flash encryption is enabled.
- Never pass PSKs or Wi-Fi passwords as command-line arguments, Bonjour TXT values, or logs.
- Guest and corporate Wi-Fi may block mDNS or peer-to-peer traffic.
- The macOS service runs as the signed-in user, never as root.
- Software-only signed update verification protects a future network update path, not an attacker with physical flash access; production physical-attack resistance requires a separately approved Secure Boot and flash-encryption provisioning ceremony.
