#!/bin/zsh

source "$(dirname "${(%):-%N}")/common.sh"

latest_changelog_entry() {
  [[ -f "$ILO_BOARD_CHANGELOG_FILE" ]] || fail "Changelog not found: $ILO_BOARD_CHANGELOG_FILE"
  awk '
    /^## / { if (seen) exit; seen = 1 }
    seen { print }
  ' "$ILO_BOARD_CHANGELOG_FILE"
}

xml_escape() {
  perl -0pe 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g'
}

sparkle_release_notes() {
  local entry line section title text
  local count=0
  local total=0
  local -a notes=()
  entry="$(latest_changelog_entry)"

  while IFS= read -r line; do
    case "$line" in
      '## '*) title="${line#\#\# }" ;;
      '### '*) section="${line#\#\#\# }" ;;
      '- '*)
        total=$((total + 1))
        if (( count < 6 )); then
          text="${line#- }"
          notes+=("- ${section:+$section: }$text")
          count=$((count + 1))
        fi
        ;;
    esac
  done <<< "$entry"

  [[ -n "${title:-}" && $total -gt 0 ]] || fail "Latest changelog entry needs a version heading and bullets."
  print -- "$title"
  print
  print -l -- "${notes[@]}"
  if (( total > count )); then
    print
    print -- "Plus $((total - count)) more changes in the full changelog."
  fi
}

sparkle_release_notes_xml() {
  local escaped
  escaped="$(sparkle_release_notes | xml_escape)"
  print -- '      <description sparkle:format="plain-text">'
  print -- "$escaped" | sed 's/^/        /'
  print -- '      </description>'
}
