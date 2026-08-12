#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

readonly version_file="${ILO_BOARD_FIRMWARE_VERSION_FILE:-$ILO_BOARD_ROOT/firmware/version.txt}"

read_version() {
  [[ -f "$version_file" ]] || fail "Firmware version file not found: $version_file"
  local value
  value="$(<"$version_file")"
  [[ "$value" == <->.<->.<-> ]] || fail "Firmware version must be major.minor.patch: $value"
  print -- "$value"
}

bump_version() {
  local part="$1"
  local current major minor patch next temporary
  current="$(read_version)"
  IFS=. read -r major minor patch <<< "$current"
  case "$part" in
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *) fail "Firmware version bump must be minor or patch." ;;
  esac
  next="$major.$minor.$patch"
  temporary="$(mktemp "${version_file}.tmp.XXXXXX")"
  print -- "$next" > "$temporary"
  mv "$temporary" "$version_file"
  log "Firmware version bumped from $current to $next."
}

case "${1:-current}" in
  current)
    print -- "ILO_BOARD_FIRMWARE_VERSION=$(read_version)"
    ;;
  bump)
    bump_version "${2:-}"
    ;;
  *)
    fail "Usage: ./scripts/firmware_version.sh [current|bump <minor|patch>]"
    ;;
esac
