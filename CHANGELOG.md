# Changelog

Notable ILO Board macOS companion changes are documented here.

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
