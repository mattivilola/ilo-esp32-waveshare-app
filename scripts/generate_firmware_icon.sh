#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

ensure_command magick
ensure_command xxd

source_png="$ILO_BOARD_PACKAGE/Sources/ILOBoardMenu/Resources/icon_round.png"
output_dir="$ILO_BOARD_ROOT/firmware/components/ui/assets"
output_c="$output_dir/ilo_icon_48.c"
output_h="$output_dir/ilo_icon_48.h"
[[ -f "$source_png" ]] || fail "Brand icon not found: $source_png"
mkdir -p "$output_dir"

temporary="$(mktemp -d /tmp/ilo-board-firmware-icon.XXXXXX)"
trap 'rm -rf "$temporary"' EXIT
raw="$temporary/icon.bgra"
magick "$source_png" -resize 48x48 -background none -gravity center -extent 48x48 "BGRA:$raw"
[[ "$(wc -c < "$raw" | tr -d ' ')" == "9216" ]] || fail "Generated icon has an unexpected byte count."

{
  print '#pragma once'
  print
  print '#include "lvgl.h"'
  print
  print 'extern const lv_image_dsc_t ilo_icon_48;'
} > "$output_h"

{
  print '#include "ilo_icon_48.h"'
  print
  print '#ifndef LV_ATTRIBUTE_MEM_ALIGN'
  print '#define LV_ATTRIBUTE_MEM_ALIGN'
  print '#endif'
  print
  xxd -i -n ilo_icon_48_map "$raw" |
    sed -e 's/^unsigned char /const LV_ATTRIBUTE_MEM_ALIGN LV_ATTRIBUTE_LARGE_CONST uint8_t /' \
        -e '/^unsigned int ilo_icon_48_map_len/d'
  print
  print 'const lv_image_dsc_t ilo_icon_48 = {'
  print '    .header.magic = LV_IMAGE_HEADER_MAGIC,'
  print '    .header.cf = LV_COLOR_FORMAT_ARGB8888,'
  print '    .header.flags = 0,'
  print '    .header.w = 48,'
  print '    .header.h = 48,'
  print '    .header.stride = 192,'
  print '    .data_size = sizeof(ilo_icon_48_map),'
  print '    .data = ilo_icon_48_map,'
  print '};'
} > "$output_c"

log "Generated firmware icon at $output_c"
