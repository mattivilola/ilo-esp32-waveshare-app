# Security model

This model covers the firmware built for the Waveshare ESP32-S3-Touch-LCD-5B (SKU 28151) and its paired macOS user service.

## Phase-1 capability

The only board capability is `tasks.read`. The host sends a normalized task ID, short title, coarse status, attention kind, timestamp, and short summary. Mutating requests fail closed.

## Pairing and transport

The intended pairing flow creates an opaque board ID and random 32-byte PSK while USB is physically connected. The host stores the PSK in the user Keychain; the board stores it in NVS. Bonjour advertises only protocol compatibility.

TLS 1.2 PSK protects the local-network link. Phase 1 validates `TLS_PSK_WITH_AES_128_GCM_SHA256` interoperability before the protocol is expanded.

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
