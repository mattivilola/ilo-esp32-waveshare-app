#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
require_firmware_signing_material
ensure_command openssl

[[ "${ILO_BOARD_FIRMWARE_RELEASE_SEQUENCE:-}" == <-> ]] || fail "Set ILO_BOARD_FIRMWARE_RELEASE_SEQUENCE to a positive integer."
(( ILO_BOARD_FIRMWARE_RELEASE_SEQUENCE > 0 )) || fail "Firmware release sequence must be positive."
[[ -n "${ILO_BOARD_FIRMWARE_RELEASE_NOTE_1:-}" ]] || fail "Set at least ILO_BOARD_FIRMWARE_RELEASE_NOTE_1."

version="$(firmware_version)"
version_parts=(${(s:.:)version})
(( version_parts[1] > 0 || version_parts[2] >= 2 )) \
  || fail "The first signed OTA bridge must be firmware 0.2.0 or newer."
release_dir="$(firmware_release_dir)"
release_image="$(firmware_release_image)"
release_manifest="$(firmware_release_manifest)"
release_sdkconfig="$(firmware_release_sdkconfig)"
build_dir="$release_dir/build"
unsigned_image="$build_dir/ilo_board.bin"

mkdir -p "$release_dir"

export ILO_BOARD_FIRMWARE_PUBLIC_KEY="${ILO_BOARD_FIRMWARE_PUBLIC_KEY:A}"
export SDKCONFIG_DEFAULTS="$ILO_BOARD_ROOT/firmware/sdkconfig.defaults;$ILO_BOARD_ROOT/firmware/sdkconfig.ota-release.defaults"
"$ILO_BOARD_ROOT/tools/idf" idf.py \
  -C "$ILO_BOARD_ROOT/firmware" \
  -B "$build_dir" \
  -D "SDKCONFIG=$release_sdkconfig" \
  -D "SDKCONFIG_DEFAULTS=$SDKCONFIG_DEFAULTS" \
  -D IDF_TARGET=esp32s3 \
  build

[[ -f "$unsigned_image" ]] || fail "Release build did not produce $unsigned_image"
"$ILO_BOARD_ROOT/tools/idf" python \
  "$ILO_BOARD_ROOT/.tools/esp-idf/components/esptool_py/esptool/espsecure.py" \
  sign_data --version 2 \
  --keyfile "$ILO_BOARD_FIRMWARE_SIGNING_KEY" \
  --output "$release_image" \
  "$unsigned_image"

"$ILO_BOARD_ROOT/tools/board" ota-verify \
  --image "$release_image" \
  --public-key "$ILO_BOARD_FIRMWARE_PUBLIC_KEY" \
  --sdkconfig "$release_sdkconfig"

typeset -a manifest_args
manifest_args=(
  create
  --image "$release_image"
  --private-key "$ILO_BOARD_FIRMWARE_SIGNING_KEY"
  --public-key "$ILO_BOARD_FIRMWARE_PUBLIC_KEY"
  --output "$release_manifest"
  --version "$version"
  --sequence "$ILO_BOARD_FIRMWARE_RELEASE_SEQUENCE"
  --minimum-updater-version "0.2.0"
  --published-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
)
typeset index note_name note
for index in {1..8}; do
  note_name="ILO_BOARD_FIRMWARE_RELEASE_NOTE_$index"
  note="${(P)note_name:-}"
  [[ -z "$note" ]] || manifest_args+=(--release-note "$note")
done
python3 "$ILO_BOARD_ROOT/tools/firmware_manifest.py" "${manifest_args[@]}"
python3 "$ILO_BOARD_ROOT/tools/firmware_manifest.py" verify \
  --manifest "$release_manifest" \
  --public-key "$ILO_BOARD_FIRMWARE_PUBLIC_KEY"

log "Signed firmware release is ready locally at $release_dir"
log "Nothing was uploaded and no board was changed."
