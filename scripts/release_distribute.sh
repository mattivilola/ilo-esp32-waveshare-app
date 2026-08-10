#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command gcloud
ensure_command xcrun
ensure_command cmp

release_dmg="$(release_dmg_path)"
latest_dmg="$(latest_dmg_path)"
appcast="$(appcast_path)"
[[ -f "$release_dmg" ]] || fail "Versioned DMG not found: $release_dmg"
[[ -f "$latest_dmg" ]] || fail "Latest DMG alias not found: $latest_dmg"
xcrun stapler validate "$release_dmg" >/dev/null || fail "Distribution requires a valid stapled notarization ticket."
cmp -s "$release_dmg" "$latest_dmg" || fail "Latest DMG alias does not match the notarized versioned DMG."

"$ILO_BOARD_ROOT/scripts/render_appcast.sh" "$release_dmg" "$appcast" >/dev/null
[[ -f "$appcast" ]] || fail "Sparkle appcast was not generated."

versioned_uri="$(public_versioned_dmg_uri)"
gcloud storage cp "$release_dmg" "$versioned_uri"
gcloud storage cp "$latest_dmg" "$ILO_BOARD_PUBLIC_RELEASE_URI"
gcloud storage cp "$appcast" "$ILO_BOARD_PUBLIC_APPCAST_URI"
log "Published $versioned_uri, $ILO_BOARD_PUBLIC_RELEASE_URI, and $ILO_BOARD_PUBLIC_APPCAST_URI"
