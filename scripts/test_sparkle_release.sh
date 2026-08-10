#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

tmp="$(mktemp -d /tmp/ilo-board-sparkle-test.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/artifacts"

cat > "$tmp/bin/sign_update" <<'EOF'
#!/bin/zsh
print -- 'sparkle:edSignature="TEST_ED_SIGNATURE" length="123"'
EOF
cat > "$tmp/bin/xcrun" <<'EOF'
#!/bin/zsh
[[ "${FAKE_STAPLER_FAILURE:-0}" == 0 ]]
EOF
cat > "$tmp/bin/gcloud" <<'EOF'
#!/bin/zsh
print -- "$*" >> "$FAKE_GCLOUD_LOG"
EOF
chmod +x "$tmp/bin/sign_update" "$tmp/bin/xcrun" "$tmp/bin/gcloud"

cat > "$tmp/release.env" <<EOF
ILO_BOARD_SPARKLE_PUBLIC_ED_KEY="TEST_PUBLIC_KEY"
ILO_BOARD_SPARKLE_TOOLS_DIR="$tmp/bin"
ILO_BOARD_PUBLIC_RELEASE_URI="gs://test/ILOBoard-latest.dmg"
ILO_BOARD_PUBLIC_VERSIONED_RELEASES_URI="gs://test/releases"
ILO_BOARD_PUBLIC_VERSIONED_RELEASES_URL="https://example.com/releases"
ILO_BOARD_PUBLIC_APPCAST_URI="gs://test/appcast.xml"
ILO_BOARD_PUBLIC_APPCAST_URL="https://example.com/appcast.xml"
EOF

release_dmg="$tmp/artifacts/ILOBoard-0.1.1.dmg"
latest_dmg="$tmp/artifacts/ILOBoard-latest.dmg"
print -n -- "notarized fixture" > "$release_dmg"
cp "$release_dmg" "$latest_dmg"

export ILO_BOARD_RELEASE_ENV="$tmp/release.env"
export ILO_BOARD_ARTIFACTS_DIR="$tmp/artifacts"
export FAKE_GCLOUD_LOG="$tmp/gcloud.log"
export PATH="$tmp/bin:$PATH"

"$ILO_BOARD_ROOT/scripts/render_appcast.sh" "$release_dmg" "$tmp/artifacts/appcast.xml" >/dev/null
grep -Fq 'sparkle:edSignature="TEST_ED_SIGNATURE"' "$tmp/artifacts/appcast.xml" || fail "Appcast signature is missing."
grep -Fq 'Version 0.1.1' "$tmp/artifacts/appcast.xml" || fail "Appcast version is missing."
grep -Fq 'Add signed Sparkle updates' "$tmp/artifacts/appcast.xml" || fail "Appcast release history is missing."

"$ILO_BOARD_ROOT/scripts/release_distribute.sh" >/dev/null
[[ "$(wc -l < "$FAKE_GCLOUD_LOG" | tr -d ' ')" == 3 ]] || fail "Expected DMG, latest alias, and appcast uploads."
tail -n 1 "$FAKE_GCLOUD_LOG" | grep -Fq 'appcast.xml gs://test/appcast.xml' || fail "Appcast must be uploaded last."

: > "$FAKE_GCLOUD_LOG"
print -n -- "stale alias" > "$latest_dmg"
if "$ILO_BOARD_ROOT/scripts/release_distribute.sh" >/dev/null 2>&1; then
  fail "Distribution accepted a stale latest alias."
fi
[[ ! -s "$FAKE_GCLOUD_LOG" ]] || fail "A failed preflight reached GCS."

log "Sparkle release tests passed"
