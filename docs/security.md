# Security model

This model covers the firmware built for the Waveshare ESP32-S3-Touch-LCD-5B (SKU 28151) and its paired macOS user service.

## Phase-1 capability

Codex and Mac-control capabilities are read-only: `tasks.read`, `macPower.read`, plus an explicitly requested diagnostic display capture. The host sends a normalized task ID, short title, coarse status, attention kind, timestamp, short summary, and optional Mac battery percentage/state. Mac power data excludes the computer name, battery serial, hardware identifiers, health/capacity history, adapter details, and time estimates. Capture returns only the pixels already visible on the paired physical display. The separate `xNews.refresh.request` capability can start only the already-opted-in bounded news adapter; all other mutating requests fail closed.

## Codex privacy boundary

The host obtains recent task metadata through a one-shot local Codex App Server `thread/list` request. Its decoder accepts only `id`, optional `name`, `updatedAt`, and `status`. Prompt previews, full turns, working-directory paths, task source metadata, Git information, file contents, environment variables, and credentials are neither decoded nor placed in the board protocol.

Results are capped at six tasks and cached for 15 seconds. A child App Server is closed after each refresh; the companion never reads or writes Codex SQLite databases, session logs, or internal state files directly.

A task reported as `notLoaded` is presented as recent history with live Desktop status unavailable. It is not presented as active, waiting for approval, or waiting for an answer. This prevents the separate companion process from overstating what it can observe.

## Pairing and transport

The pairing flow creates an opaque board ID and random 32-byte PSK while USB is physically connected. The host stores the PSK in the user Keychain; the board stores it in NVS. Because CLI provisioning and the Developer ID app are distinct signed clients, the app never reads the CLI-owned item silently at startup. It first presents a bounded explanation and requires an explicit button press; only then can the macOS password dialog appear. After that authorized read, the app writes an app-owned Keychain copy for its stable bundle/signing identity, so later launches and signed updates do not repeatedly prompt. The CLI-owned item remains in Keychain for headless and diagnostic commands. Neither copy is exported, logged, placed in preferences, or written to the repository.

Bonjour TXT advertises only protocol compatibility (`v=1`, `transport=tls-psk-tcp`), not the board ID or secret. The service instance contains only the final eight characters already used in its nonsecret display name; firmware uses it to avoid unrelated compatible hosts, then relies on TLS-PSK and the protocol hello for authoritative pairing identity. Failed or blocked discovery falls back to the provisioned endpoint without weakening authentication.

`./tools/board provision` reads the Wi-Fi password without terminal echo and sends the key material to the host CLI through standard input, never through process arguments. Its NVS CSV and binary exist only in a permission-restricted temporary directory for the duration of the verified partition write. The persistent host metadata file contains only the nonsecret board ID, protocol version, and service port.

TLS 1.2 PSK protects the local-network link. Phase 1 validates `TLS_PSK_WITH_AES_128_GCM_SHA256` interoperability before the protocol is expanded.

Live framebuffer capture has no unauthenticated HTTP or discovery endpoint. The request is accepted only inside an established paired TLS session after the version-1 hello/subscription exchange. Firmware accepts a bounded request ID and exactly one format/size, copies the framebuffer into temporary PSRAM, sends fixed-size sequenced chunks, attaches a SHA-256 result, then frees the copy. The Mac rejects unsolicited, mismatched, duplicate, reordered, truncated, oversized, or corrupt capture data and refuses to overwrite an output path unless the operator passes `--force`.

OTA delivery is disabled. The compiled foundation has two equal application slots and ESP-IDF rollback: a pending image is not marked valid until core display/UI initialization and a 30-second stability/heap check pass. The release-only profile requires RSA-signed application updates, while `ota-verify` refuses private keys and blocks invalid images, unsafe sdkconfig files, bad signatures, and oversized artifacts. No private signing key, update URL, upload credential, or automatic installer is stored in the project. Hardware Secure Boot, flash encryption, anti-rollback eFuses, key custody, update hosting, and actual delivery remain explicit production gates.

Direct weather is the only current board-originated Internet request. It sends configured latitude/longitude and ordinary HTTP metadata to `api.open-meteo.com`; it sends no board ID, pairing secret, Wi-Fi password, Codex data, or Mac data. The response is bounded to 8 KiB and HTTPS uses ESP-IDF's CA certificate bundle after SNTP clock synchronization. Weather is optional public-data access, not a general proxy or arbitrary URL feature.

The authenticated companion snapshot may include only the Mac's current bounded UTC offset and timezone abbreviation for local clock display. It does not transmit the IANA timezone identifier, locale, location, system clock history, or other regional settings. The board obtains absolute time independently through SNTP.

Optional X News remains Mac-mediated and disabled by default. Enabling it requires either explicit CLI consent or the companion’s confirmation dialog because the authenticated Grok process uses `--yolo` for X search and may consume paid capacity. Missing Grok or an Off schedule sends a false visibility flag and hides the complete board page; the ESP32 cannot enable it. The process runs from an isolated temporary directory with memory/subagents disabled, a three-minute deadline, and a 1 MB output cap. Output is rejected unless bounded stories contain matching direct X status URLs whose Snowflake timestamps independently fall inside the requested 24-hour window. Invalid output never replaces the previous cache. Only the visibility flag and verified bounded cache cross TLS to the board; Grok/X credentials, reasoning, sessions, prompts, usage, stderr, and raw output stay off the wire.

Pull-to-refresh is a narrow authenticated request, not a general command channel. It is accepted only after TLS hello/subscription, carries a random bounded request ID and no prompt, and cannot enable Grok consent. The Mac independently enforces opt-in, a 15-minute cost cooldown, one process at a time, the same three-minute timeout/validator, and last-good-cache preservation. The board receives only one of six coarse result states and never sees raw process errors.

The Mac companion update channel is separate from firmware OTA. Public releases are Developer-ID signed, notarized, stapled, and additionally signed with Sparkle EdDSA. The private update key remains in the login Keychain; only its public key is embedded in the app. The HTTPS appcast contains bounded changelog text and an immutable versioned GCS URL. Distribution validates the stapled DMG and byte-identical latest alias before signing, then uploads the appcast last. A compromised public bucket cannot produce an accepted replacement DMG without the Apple and EdDSA signing identities.

Ad-hoc `make app` builds use `disable-library-validation` only so a Team-ID-less development executable can load the prebuilt Sparkle framework. `sign_release.sh` never applies that entitlement: Developer ID releases explicitly re-sign Sparkle's nested helpers/framework and the app with the same Apple identity before notarization.

## Explicit exclusions

The device cannot currently:

- approve commands or file changes;
- grant additional permissions;
- use `acceptForSession` or policy amendments;
- answer free-form or structured Codex questions;
- start, steer, or interrupt Codex turns;
- run shell commands or AppleScript;
- read or write Codex SQLite/session files.

Later decision support requires one-time request IDs, expiry, replay protection, current-state validation, complete action context, an audit trail, and a visible Mac-side revocation control. File-change approval remains Mac-only unless a device can present enough of the diff for informed consent.

## Development caveats

- ESP NVS is not resistant to physical extraction until NVS/flash encryption is enabled.
- Never pass PSKs or Wi-Fi passwords as command-line arguments, Bonjour TXT values, or logs.
- Guest and corporate Wi-Fi may block mDNS or peer-to-peer traffic.
- The macOS service runs as the signed-in user, never as root.
- Software-only signed update verification protects a future network update path, not an attacker with physical flash access; production physical-attack resistance requires a separately approved Secure Boot and flash-encryption provisioning ceremony.
