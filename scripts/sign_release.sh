#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command codesign
require_signing_identity

app_path="$(release_app_path)"
[[ -d "$app_path" ]] || fail "App bundle not found. Run make app first."

require_sparkle_public_key
validate_sparkle_configuration "$app_path"
sign_sparkle_framework "$app_path" "$ILO_BOARD_SIGNING_IDENTITY"
codesign --force --options runtime --timestamp --sign "$ILO_BOARD_SIGNING_IDENTITY" "$app_path"
codesign --verify --deep --strict "$app_path"

dmg_path="$(release_dmg_path)"
if [[ -f "$dmg_path" ]]; then
  codesign --force --timestamp --sign "$ILO_BOARD_SIGNING_IDENTITY" "$dmg_path"
  codesign --verify --strict "$dmg_path"
fi

log "Developer ID signature verified"
