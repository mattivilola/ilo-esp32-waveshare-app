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
  firmware_key_create.sh \
  firmware_release_local.sh \
  firmware_release_flash.sh \
  firmware_release_distribute.sh \
  release_commit.sh \
  release_tag.sh \
  release_push.sh \
  release_local.sh \
  release_distribute.sh \
  capture_board_screenshot.sh \
  test_sparkle_release.sh; do
  zsh -n "$ILO_BOARD_ROOT/scripts/$script"
done

zsh -n "$ILO_BOARD_ROOT/scripts/lib/firmware_key.sh"

firmware_version_test_dir="$(mktemp -d)"
trap 'rm -rf "$firmware_version_test_dir"' EXIT
key_test_dir="$firmware_version_test_dir/key"
mkdir -p "$key_test_dir"
umask 077
openssl rand -base64 24 > "$key_test_dir/passphrase"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
  -aes-256-cbc -pass "file:$key_test_dir/passphrase" \
  -out "$key_test_dir/encrypted.pem" >/dev/null 2>&1
KEY_TEST_DIR="$key_test_dir" zsh -c '
  source scripts/lib/common.sh
  source scripts/lib/firmware_key.sh
  firmware_key_passphrase_dialog() { < "$KEY_TEST_DIR/passphrase"; }
  unlock_firmware_signing_key "$KEY_TEST_DIR/encrypted.pem" "$KEY_TEST_DIR/plain.pem"
  [[ "$(stat -f %Lp "$KEY_TEST_DIR/plain.pem")" == 600 ]]
  openssl pkey -in "$KEY_TEST_DIR/plain.pem" -check -noout >/dev/null 2>&1
  grep -Fq -- "-----BEGIN ENCRYPTED PRIVATE KEY-----" "$KEY_TEST_DIR/encrypted.pem"
'

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
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.personal-information.location' "$ILO_BOARD_ROOT/Packaging/Debug.entitlements")" == true ]] || fail "Ad-hoc app signing must allow consent-gated weather location access."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.personal-information.location' "$ILO_BOARD_ROOT/Packaging/Release.entitlements")" == true ]] || fail "Developer ID signing must allow consent-gated weather location access."
if grep -Fq 'disable-library-validation' "$ILO_BOARD_ROOT/Packaging/Release.entitlements"; then
  fail "Developer ID release entitlements must not disable library validation."
fi
grep -Fq 'Release.entitlements' "$ILO_BOARD_ROOT/scripts/sign_release.sh" || fail "Developer ID signing must apply the release entitlements."
if grep -Fq 'Debug.entitlements' "$ILO_BOARD_ROOT/scripts/sign_release.sh"; then
  fail "Developer ID release signing must not use debug entitlements."
fi
grep -Fq 'stapler validate' "$ILO_BOARD_ROOT/scripts/release_distribute.sh" || fail "Distribution must require notarization validation."
grep -Fq 'cmp -s' "$ILO_BOARD_ROOT/scripts/release_distribute.sh" || fail "Distribution must reject a stale latest alias."
grep -Fq 'SUPublicEDKey' "$ILO_BOARD_ROOT/Packaging/Info.plist" "$ILO_BOARD_ROOT/scripts/build_app.sh" || fail "Release packaging must inject a Sparkle public key."
grep -Fq 'appcast' "$ILO_BOARD_ROOT/scripts/release_distribute.sh" || fail "Distribution must publish the Sparkle appcast."
grep -Fq -- '--if-generation-match=0' "$ILO_BOARD_ROOT/scripts/firmware_release_distribute.sh" || fail "Firmware distribution must forbid immutable artifact replacement."
grep -Fq 'cmp -s' "$ILO_BOARD_ROOT/scripts/firmware_release_distribute.sh" || fail "Firmware distribution must verify the uploaded image before publishing the manifest."
grep -Fq 'firmware_manifest.py" verify' "$ILO_BOARD_ROOT/scripts/firmware_release_distribute.sh" || fail "Firmware distribution must verify the signed manifest."
grep -Fq 'require_firmware_public_key' "$ILO_BOARD_ROOT/scripts/firmware_release_distribute.sh" || fail "Firmware distribution must require only public verification material."
! grep -Fq 'require_firmware_signing_material' "$ILO_BOARD_ROOT/scripts/firmware_release_distribute.sh" || fail "Firmware distribution must not require the private signing key."
grep -Fq '0x9000 was preserved' "$ILO_BOARD_ROOT/scripts/firmware_release_flash.sh" || fail "Signed bridge flashing must document preserved NVS."
grep -Fq 'require_firmware_public_key' "$ILO_BOARD_ROOT/scripts/firmware_release_flash.sh" || fail "Signed bridge flashing must require only public verification material."
! grep -Fq 'require_firmware_signing_material' "$ILO_BOARD_ROOT/scripts/firmware_release_flash.sh" || fail "Signed bridge flashing must not require the private signing key."
grep -Fq 'unlock_firmware_signing_key' "$ILO_BOARD_ROOT/scripts/firmware_release_local.sh" || fail "Local firmware releases must unlock encrypted keys only for signing."
! grep -Eq -- '-pass(in)?[= ]+pass:' "$ILO_BOARD_ROOT/scripts/firmware_key_create.sh" "$ILO_BOARD_ROOT/scripts/lib/firmware_key.sh" || fail "Firmware key passphrases must not appear in process arguments."

"$ILO_BOARD_ROOT/scripts/test_sparkle_release.sh"

log "Release tooling checks passed"
