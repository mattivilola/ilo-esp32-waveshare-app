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
  release_local.sh \
  release_distribute.sh; do
  zsh -n "$ILO_BOARD_ROOT/scripts/$script"
done

grep -Fq 'LSUIElement' "$ILO_BOARD_ROOT/Packaging/Info.plist" || fail "Packaged app must remain menu-bar only."
grep -Fq '_iloboard._tcp' "$ILO_BOARD_ROOT/Packaging/Info.plist" || fail "Packaged app must declare its Bonjour service."
grep -Fq 'stapler validate' "$ILO_BOARD_ROOT/scripts/release_distribute.sh" || fail "Distribution must require notarization validation."
grep -Fq 'cmp -s' "$ILO_BOARD_ROOT/scripts/release_distribute.sh" || fail "Distribution must reject a stale latest alias."

log "Release tooling checks passed"
