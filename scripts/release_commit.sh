#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command git
current_branch >/dev/null
[[ -f "$ILO_BOARD_CHANGELOG_FILE" ]] || fail "CHANGELOG.md is missing."
git diff --quiet -- "$ILO_BOARD_VERSION_FILE" "$ILO_BOARD_CHANGELOG_FILE" && fail "No prepared release metadata changes found."
git add "$ILO_BOARD_VERSION_FILE" "$ILO_BOARD_CHANGELOG_FILE"
git commit -m "Release v$ILO_BOARD_MARKETING_VERSION"
log "Committed release v$ILO_BOARD_MARKETING_VERSION."
