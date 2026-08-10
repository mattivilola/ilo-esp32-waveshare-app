#!/bin/zsh

if [[ -n "${ILO_BOARD_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi

ILO_BOARD_COMMON_SH_LOADED=1

readonly ILO_BOARD_COMMON_SCRIPT="${(%):-%N}"
export ILO_BOARD_ROOT="$(cd "${ILO_BOARD_COMMON_SCRIPT:A:h:h:h}" && pwd)"
export ILO_BOARD_PACKAGE="$ILO_BOARD_ROOT/mac-service"
export ILO_BOARD_ARTIFACTS_DIR="${ILO_BOARD_ARTIFACTS_DIR:-$ILO_BOARD_ROOT/artifacts}"
export ILO_BOARD_VERSION_FILE="${ILO_BOARD_VERSION_FILE:-$ILO_BOARD_ROOT/Config/version.env}"

log() {
  print -- "[ilo-board] $*"
}

fail() {
  print -u2 -- "[ilo-board] error: $*"
  exit 1
}

ensure_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

load_release_config() {
  [[ -f "$ILO_BOARD_VERSION_FILE" ]] || fail "Version file not found: $ILO_BOARD_VERSION_FILE"
  source "$ILO_BOARD_VERSION_FILE"
  local release_env="$ILO_BOARD_ROOT/Config/release.env"
  if [[ -f "$release_env" ]]; then
    source "$release_env"
  fi
  export ILO_BOARD_APP_NAME="${ILO_BOARD_APP_NAME:-ILO Board}"
  export ILO_BOARD_EXECUTABLE="${ILO_BOARD_EXECUTABLE:-ILOBoardMenu}"
  export ILO_BOARD_BUNDLE_ID="${ILO_BOARD_BUNDLE_ID:-com.iloapps.iloboard.menu}"
  export ILO_BOARD_PUBLIC_RELEASE_URI="${ILO_BOARD_PUBLIC_RELEASE_URI:-gs://ilo-public/ilo-board/ILOBoard-latest.dmg}"
  export ILO_BOARD_PUBLIC_VERSIONED_RELEASES_URI="${ILO_BOARD_PUBLIC_VERSIONED_RELEASES_URI:-gs://ilo-public/ilo-board/releases}"
}

release_basename() {
  print -- "ILOBoard-${ILO_BOARD_MARKETING_VERSION}"
}

release_app_path() {
  print -- "$ILO_BOARD_ARTIFACTS_DIR/${ILO_BOARD_APP_NAME}.app"
}

release_dmg_path() {
  print -- "$ILO_BOARD_ARTIFACTS_DIR/$(release_basename).dmg"
}

latest_dmg_path() {
  print -- "$ILO_BOARD_ARTIFACTS_DIR/ILOBoard-latest.dmg"
}

require_signing_identity() {
  [[ -n "${ILO_BOARD_SIGNING_IDENTITY:-}" ]] || fail "Set ILO_BOARD_SIGNING_IDENTITY in Config/release.env."
  security find-identity -v -p codesigning | grep -Fq "\"$ILO_BOARD_SIGNING_IDENTITY\"" || fail "Signing identity is not available in this Keychain: $ILO_BOARD_SIGNING_IDENTITY"
}

require_notary_profile() {
  [[ -n "${ILO_BOARD_NOTARY_PROFILE:-}" ]] || fail "Set ILO_BOARD_NOTARY_PROFILE in Config/release.env."
}
