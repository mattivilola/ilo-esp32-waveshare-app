#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command hdiutil
ensure_command ditto

app_path="$(release_app_path)"
dmg_path="$(release_dmg_path)"
[[ -d "$app_path" ]] || fail "App bundle not found. Run make app first."
mkdir -p "$ILO_BOARD_ARTIFACTS_DIR"

stage="$(mktemp -d /tmp/ilo-board-dmg.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
ditto "$app_path" "$stage/${ILO_BOARD_APP_NAME}.app"
ln -s /Applications "$stage/Applications"

hdiutil create -volname "$ILO_BOARD_APP_NAME" -srcfolder "$stage" -format UDZO -ov "$dmg_path" >/dev/null
log "Created DMG at $dmg_path"
