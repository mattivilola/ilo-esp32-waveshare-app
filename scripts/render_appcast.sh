#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/release_notes.sh"

load_release_config
ensure_command xmllint

release_dmg="${1:-$(release_dmg_path)}"
output="${2:-$(appcast_path)}"
[[ -f "$release_dmg" ]] || fail "Release DMG not found: $release_dmg"

sign_update="$(sparkle_tool_path sign_update)"
signature_output="$("$sign_update" "$release_dmg")"
signature="$(print -- "$signature_output" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
[[ -n "$signature" ]] || fail "Sparkle sign_update did not return an EdDSA signature."

mkdir -p "${output:h}"
publication_date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
release_size="$(stat -f '%z' "$release_dmg")"
release_notes="$(sparkle_release_notes_xml)"

cat > "$output" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>ILO Board Updates</title>
    <link>${ILO_BOARD_PUBLIC_APPCAST_URL}</link>
    <description>Verified ILO Board macOS companion releases</description>
    <language>en</language>
    <item>
      <title>Version ${ILO_BOARD_MARKETING_VERSION}</title>
      <pubDate>${publication_date}</pubDate>
${release_notes}
      <enclosure
        url="$(public_versioned_dmg_url)"
        sparkle:version="${ILO_BOARD_BUILD_NUMBER}"
        sparkle:shortVersionString="${ILO_BOARD_MARKETING_VERSION}"
        sparkle:edSignature="${signature}"
        length="${release_size}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

xmllint --noout "$output"
print -- "$output"
