#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command git

bump_semver() {
  local part="$1"
  local version="$2"
  local major minor patch
  IFS=. read -r major minor patch <<< "$version"
  [[ "$major" == <-> && "$minor" == <-> && "$patch" == <-> ]] || fail "Version must be major.minor.patch: $version"
  case "$part" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *) fail "Version bump must be major, minor, or patch." ;;
  esac
  print -- "$major.$minor.$patch"
}

render_sections() {
  local previous_tag="$1"
  local range subject normalized category
  local -a added=() changed=() fixed=() security=() docs=()
  range="HEAD"
  [[ -z "$previous_tag" ]] || range="$previous_tag..HEAD"

  while IFS= read -r subject; do
    [[ -n "$subject" && "$subject" != Release\ v* ]] || continue
    normalized="${subject%.}"
    case "${(L)normalized}" in
      *security*|*secure*|*privacy*|*credential*|*keychain*) security+=("$normalized") ;;
      fix*|correct*|prevent*|resolve*) fixed+=("$normalized") ;;
      document*|docs:*|*readme*) docs+=("$normalized") ;;
      add*|implement*|create*|introduce*|support*|integrate*) added+=("$normalized") ;;
      *) changed+=("$normalized") ;;
    esac
  done < <(git log "$range" --reverse --no-merges --format='%s')

  local emitted=0
  local heading item
  for heading in Added Changed Fixed Security Documentation; do
    local -a items=()
    case "$heading" in
      Added) items=("${added[@]}") ;;
      Changed) items=("${changed[@]}") ;;
      Fixed) items=("${fixed[@]}") ;;
      Security) items=("${security[@]}") ;;
      Documentation) items=("${docs[@]}") ;;
    esac
    (( ${#items[@]} > 0 )) || continue
    print -- "### $heading"
    for item in "${items[@]}"; do print -- "- $item"; done
    print
    emitted=1
  done
  (( emitted == 1 )) || fail "No commits are available for the next changelog entry."
}

prepare_bump() {
  local part="$1"
  local next_version next_build previous_tag sections existing tmp
  ensure_clean_worktree
  next_version="$(bump_semver "$part" "$ILO_BOARD_MARKETING_VERSION")"
  next_build="$((ILO_BOARD_BUILD_NUMBER + 1))"
  git rev-parse -q --verify "refs/tags/v$next_version" >/dev/null 2>&1 && fail "Tag v$next_version already exists."
  previous_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
  sections="$(render_sections "$previous_tag")"
  existing=""
  if [[ -f "$ILO_BOARD_CHANGELOG_FILE" ]]; then
    existing="$(awk 'NR > 3 { print }' "$ILO_BOARD_CHANGELOG_FILE")"
  fi

  tmp="$(mktemp)"
  {
    print -- "# Changelog"
    print
    print -- "Notable ILO Board macOS companion changes are documented here."
    print
    print -- "## $next_version - $(date +%Y-%m-%d)"
    print
    print -- "$sections"
    [[ -z "$existing" ]] || { print; print -- "$existing"; }
  } > "$tmp"
  mv "$tmp" "$ILO_BOARD_CHANGELOG_FILE"

  print -- "ILO_BOARD_MARKETING_VERSION=\"$next_version\"" > "$ILO_BOARD_VERSION_FILE"
  print -- "ILO_BOARD_BUILD_NUMBER=\"$next_build\"" >> "$ILO_BOARD_VERSION_FILE"
  log "Prepared $next_version ($next_build). Review CHANGELOG.md, then run make release-commit."
}

case "${1:-current}" in
  current)
    print -- "ILO_BOARD_MARKETING_VERSION=$ILO_BOARD_MARKETING_VERSION"
    print -- "ILO_BOARD_BUILD_NUMBER=$ILO_BOARD_BUILD_NUMBER"
    ;;
  bump)
    prepare_bump "${2:-}"
    ;;
  *) fail "Usage: ./scripts/version.sh [current|bump <major|minor|patch>]" ;;
esac
