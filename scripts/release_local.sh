#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
"$ILO_BOARD_ROOT/scripts/build_app.sh"
"$ILO_BOARD_ROOT/scripts/sign_release.sh"
"$ILO_BOARD_ROOT/scripts/package_dmg.sh"
"$ILO_BOARD_ROOT/scripts/sign_release.sh"
"$ILO_BOARD_ROOT/scripts/notarize.sh"
"$ILO_BOARD_ROOT/scripts/staple.sh"
cp "$(release_dmg_path)" "$(latest_dmg_path)"
log "Release is ready at $(release_dmg_path)"
