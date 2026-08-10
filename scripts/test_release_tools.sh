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
  release_commit.sh \
  release_tag.sh \
  release_push.sh \
  release_local.sh \
  release_distribute.sh \
  test_sparkle_release.sh; do
  zsh -n "$ILO_BOARD_ROOT/scripts/$script"
done

grep -Fq 'LSUIElement' "$ILO_BOARD_ROOT/Packaging/Info.plist" || fail "Packaged app must remain menu-bar only."
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
