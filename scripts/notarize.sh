#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command xcrun
require_notary_profile

dmg_path="${1:-$(release_dmg_path)}"
[[ -f "$dmg_path" ]] || fail "DMG not found: $dmg_path"
xcrun notarytool submit "$dmg_path" --keychain-profile "$ILO_BOARD_NOTARY_PROFILE" --wait
log "Apple notarization completed for $dmg_path"
