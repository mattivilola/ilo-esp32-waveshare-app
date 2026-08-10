#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command sips
ensure_command iconutil

source_png="$ILO_BOARD_PACKAGE/Sources/ILOBoardMenu/Resources/icon_round.png"
output="${1:-$ILO_BOARD_ARTIFACTS_DIR/AppIcon.icns}"
[[ -f "$source_png" ]] || fail "Brand icon not found: $source_png"
mkdir -p "${output:h}"

temporary="$(mktemp -d /tmp/ilo-board-icon.XXXXXX)"
trap 'rm -rf "$temporary"' EXIT
iconset="$temporary/AppIcon.iconset"
mkdir -p "$iconset"

for specification in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"; do
  size="${specification%% *}"
  name="${specification#* }"
  sips -z "$size" "$size" "$source_png" --out "$iconset/$name" >/dev/null
done

iconutil --convert icns "$iconset" --output "$output"
log "Created app icon at $output"
