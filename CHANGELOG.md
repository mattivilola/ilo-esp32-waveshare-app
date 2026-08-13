# Changelog

Notable ILO Board macOS companion changes are documented here.

## 0.1.8 - 2026-08-13

### Added
- Add standalone mode without Codex
- Add battery-backed RTC clock fallback
- Add resilient authenticated USB fallback
- Add RTC-backed Focus Cockpit with pause, extension, task attachment, and Mac completion notifications
- Add the animated ILO PET Lando to the right third of the Pulse screensaver
- Allow holding the Settings screensaver row to show Pulse and ILO PET immediately

### Changed
- Make Wi-Fi scanning deterministic
- Bump firmware to 0.2.5
- Scan Finland Wi-Fi channels
- Bump firmware to 0.2.6
- Prepare firmware 0.2.7
- Record RTC hardware write validation
- Tolerate duplicate USB handshake hello
- Reduce memory pressure across USB and Wi-Fi


## 0.1.7 - 2026-08-13

### Added
- Show when the provisioned ESP32-S3 board is physically attached by USB, independently from its active data connection.
- Fall back to an authenticated, encrypted USB connection when Wi-Fi sync is unavailable, while keeping Wi-Fi primary when it recovers.
- Let the board open a bounded, read-only excerpt of recent Codex chat without exposing commands, tool output, reasoning, paths, or approvals.
- Add signed firmware update and rollback foundations with verified manifests and explicit install controls.

### Changed
- Improve the Mac location-permission flow with clear permission, retry, timeout, and System Settings actions.
- Report the active Wi-Fi or USB transport in both the Mac companion and board UI.
- Update the bundled board firmware to 0.2.5 with USB transport support and display/runtime stability improvements.

### Fixed
- Preserve task identity while reading related Codex chat.
- Prevent Pulse/display rendering stalls and improve on-board Wi-Fi setup recovery.

### Security
- Authenticate USB peers with the provisioned board key and protect each ordered frame with a fresh ChaCha20-Poly1305 session.


## 0.1.6 - 2026-08-12

### Changed
- Redesign Mac companion dashboard


## 0.1.5 - 2026-08-12

### Added
- Add consent-gated Codex continue action
- Add consent-gated Codex continue firmware
- Add standalone networking and companion handoffs

### Changed
- Polish dashboard weather and board glyphs
- Align Pulse screensaver content


## 0.1.4 - 2026-08-12

### Added
- Add one-command board screenshot capture
- Add non-blocking Pulse boot animation

### Changed
- Polish physical X News refresh experience
- Make board screenshot reconnect automatic
- Track firmware and companion versions
- Use the paired Mac's configured timezone for the board clock, including automatic DST updates and weather fallback

### Fixed
- Fix authenticated board screenshot transfer

### Documentation
- Document refined ILO beacon boot effect


## 0.1.3 - 2026-08-12

### Fixed
- Mutable release links now revalidate instead of serving an older cached download.
- Launch at login now offers Enable on a fresh signed installation and can create its first macOS Background Item record.

## 0.1.2 - 2026-08-11

### Added
- The Mac companion can enable or disable the optional X News screen.

### Changed
- Board and preview navigation now use four pages when X News is off and five when it is enabled.

### Fixed
- Secure pairing access is explained before the macOS Keychain prompt and remembered for later launches and signed updates.

## 0.1.1 - 2026-08-10

### Added
- Add signed Sparkle updates from the public Google Cloud Storage feed
- Show the installed app version and a Check for Updates action in the menu companion
- Add safe patch, minor, and major version preparation commands

### Changed
- Publish versioned DMG, stable download alias, and appcast in a fail-closed order
- Include bounded release history in the Sparkle update dialog

### Fixed
- Fix pointer-drag scrolling and visible refresh feedback in the X News preview

### Security
- Require Developer ID, notarization, and a Keychain-backed EdDSA signature before publishing an update
