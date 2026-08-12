#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
require_firmware_public_key
port="${1:-}"
[[ -n "$port" ]] || fail "Pass the exact connected board port, for example: make firmware-release-flash PORT=/dev/cu.usbmodem101"
[[ -e "$port" ]] || fail "Board serial port does not exist: $port"

release_image="$(firmware_release_image)"
release_sdkconfig="$(firmware_release_sdkconfig)"
release_build="$(firmware_release_dir)/build"
bootloader="$release_build/bootloader/bootloader.bin"
partition_table="$release_build/partition_table/partition-table.bin"
ota_data="$release_build/ota_data_initial.bin"
for artifact in "$release_image" "$release_sdkconfig" "$bootloader" "$partition_table" "$ota_data"; do
  [[ -f "$artifact" ]] || fail "Signed bridge artifact is incomplete: $artifact"
done

"$ILO_BOARD_ROOT/tools/board" ota-verify \
  --image "$release_image" \
  --public-key "$ILO_BOARD_FIRMWARE_PUBLIC_KEY" \
  --sdkconfig "$release_sdkconfig"

"$ILO_BOARD_ROOT/.tools/board-python/bin/esptool" \
  --chip esp32s3 --port "$port" \
  write-flash \
  --flash-mode dio --flash-size 16MB --flash-freq 80m \
  0x0 "$bootloader" \
  0x8000 "$partition_table" \
  0xf000 "$ota_data" \
  0x20000 "$release_image"

log "Signed bridge flashed and verified. NVS at 0x9000 was preserved."
log "Press RESET once if the board does not restart automatically, then allow the 30-second health window."
