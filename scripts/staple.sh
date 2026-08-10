#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command xcrun

dmg_path="${1:-$(release_dmg_path)}"
[[ -f "$dmg_path" ]] || fail "DMG not found: $dmg_path"
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
log "Notarization ticket stapled and validated"
