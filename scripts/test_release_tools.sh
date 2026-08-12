#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config

for script in \
  build_icon.sh \
  generate_firmware_icon.sh \
  build_app.sh \
  package_dmg.sh \
  sign_release.sh \
  notarize.sh \
  staple.sh \
  sparkle_keys.sh \
  render_appcast.sh \
  version.sh \
  firmware_version.sh \
  release_commit.sh \
  release_tag.sh \
  release_push.sh \
  release_local.sh \
  release_distribute.sh \
  capture_board_screenshot.sh \
  test_sparkle_release.sh; do
  zsh -n "$ILO_BOARD_ROOT/scripts/$script"
done

firmware_version_test_dir="$(mktemp -d)"
trap 'rm -rf "$firmware_version_test_dir"' EXIT
firmware_version_test_file="$firmware_version_test_dir/version.txt"
print -- "1.2.3" > "$firmware_version_test_file"
ILO_BOARD_FIRMWARE_VERSION_FILE="$firmware_version_test_file" "$ILO_BOARD_ROOT/scripts/firmware_version.sh" bump patch >/dev/null
grep -Fxq "1.2.4" "$firmware_version_test_file" || fail "Firmware patch bump produced the wrong version."
ILO_BOARD_FIRMWARE_VERSION_FILE="$firmware_version_test_file" "$ILO_BOARD_ROOT/scripts/firmware_version.sh" bump minor >/dev/null
grep -Fxq "1.3.0" "$firmware_version_test_file" || fail "Firmware minor bump produced the wrong version."

grep -Fq 'LSUIElement' "$ILO_BOARD_ROOT/Packaging/Info.plist" || fail "Packaged app must remain menu-bar only."
grep -Fq 'ILOSupportsPromptFreeScreenCapture' "$ILO_BOARD_ROOT/Packaging/Info.plist" || fail "Packaged app must advertise stable-identity screen capture support."
grep -Fq 'NSLocationUsageDescription' "$ILO_BOARD_ROOT/Packaging/Info.plist" || fail "Packaged app must explain optional weather location use."
grep -Fq '_iloboard._tcp' "$ILO_BOARD_ROOT/Packaging/Info.plist" || fail "Packaged app must declare its Bonjour service."
grep -Fq 'disable-library-validation' "$ILO_BOARD_ROOT/Packaging/Debug.entitlements" || fail "Ad-hoc Sparkle builds need the documented debug library-validation exception."
if grep -Fq 'Debug.entitlements' "$ILO_BOARD_ROOT/scripts/sign_release.sh"; then
  fail "Developer ID release signing must not use debug entitlements."
fi
grep -Fq 'stapler validate' "$ILO_BOARD_ROOT/scripts/release_distribute.sh" || fail "Distribution must require notarization validation."
grep -Fq 'cmp -s' "$ILO_BOARD_ROOT/scripts/release_distribute.sh" || fail "Distribution must reject a stale latest alias."
grep -Fq 'SUPublicEDKey' "$ILO_BOARD_ROOT/Packaging/Info.plist" "$ILO_BOARD_ROOT/scripts/build_app.sh" || fail "Release packaging must inject a Sparkle public key."
grep -Fq 'appcast' "$ILO_BOARD_ROOT/scripts/release_distribute.sh" || fail "Distribution must publish the Sparkle appcast."

"$ILO_BOARD_ROOT/scripts/test_sparkle_release.sh"

log "Release tooling checks passed"
