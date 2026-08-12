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
export ILO_BOARD_CHANGELOG_FILE="${ILO_BOARD_CHANGELOG_FILE:-$ILO_BOARD_ROOT/CHANGELOG.md}"

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
  local release_env="${ILO_BOARD_RELEASE_ENV:-$ILO_BOARD_ROOT/Config/release.env}"
  if [[ -f "$release_env" ]]; then
    source "$release_env"
  fi
  export ILO_BOARD_APP_NAME="${ILO_BOARD_APP_NAME:-ILO Board}"
  export ILO_BOARD_EXECUTABLE="${ILO_BOARD_EXECUTABLE:-ILOBoardMenu}"
  export ILO_BOARD_BUNDLE_ID="${ILO_BOARD_BUNDLE_ID:-com.iloapps.iloboard.menu}"
  export ILO_BOARD_PUBLIC_RELEASE_URI="${ILO_BOARD_PUBLIC_RELEASE_URI:-gs://ilo-public/ilo-board/ILOBoard-latest.dmg}"
  export ILO_BOARD_PUBLIC_VERSIONED_RELEASES_URI="${ILO_BOARD_PUBLIC_VERSIONED_RELEASES_URI:-gs://ilo-public/ilo-board/releases}"
  export ILO_BOARD_PUBLIC_VERSIONED_RELEASES_URL="${ILO_BOARD_PUBLIC_VERSIONED_RELEASES_URL:-https://storage.googleapis.com/ilo-public/ilo-board/releases}"
  export ILO_BOARD_PUBLIC_APPCAST_URI="${ILO_BOARD_PUBLIC_APPCAST_URI:-gs://ilo-public/ilo-board/appcast.xml}"
  export ILO_BOARD_PUBLIC_APPCAST_URL="${ILO_BOARD_PUBLIC_APPCAST_URL:-https://storage.googleapis.com/ilo-public/ilo-board/appcast.xml}"
  export ILO_BOARD_FIRMWARE_RELEASES_URI="${ILO_BOARD_FIRMWARE_RELEASES_URI:-gs://ilo-public/ilo-board/firmware/releases}"
  export ILO_BOARD_FIRMWARE_MANIFEST_URI="${ILO_BOARD_FIRMWARE_MANIFEST_URI:-gs://ilo-public/ilo-board/firmware/manifest-v1.json}"
}

firmware_version() {
  local version
  version="$(<"$ILO_BOARD_ROOT/firmware/version.txt")"
  [[ "$version" == <->.<->.<-> ]] || fail "Firmware version must be major.minor.patch: $version"
  print -- "$version"
}

firmware_release_dir() {
  print -- "$ILO_BOARD_ARTIFACTS_DIR/firmware/$(firmware_version)"
}

firmware_release_image() {
  print -- "$(firmware_release_dir)/ILOBoardFirmware-$(firmware_version).bin"
}

firmware_release_manifest() {
  print -- "$(firmware_release_dir)/manifest-v1.json"
}

firmware_release_sdkconfig() {
  print -- "$(firmware_release_dir)/sdkconfig"
}

require_firmware_public_key() {
  [[ -n "${ILO_BOARD_FIRMWARE_PUBLIC_KEY:-}" ]] || fail "Set ILO_BOARD_FIRMWARE_PUBLIC_KEY to its PEM public key path."
  [[ -f "$ILO_BOARD_FIRMWARE_PUBLIC_KEY" ]] || fail "Firmware public key does not exist."
}

require_firmware_signing_material() {
  require_firmware_public_key
  [[ -n "${ILO_BOARD_FIRMWARE_SIGNING_KEY:-}" ]] || fail "Set ILO_BOARD_FIRMWARE_SIGNING_KEY to the external RSA-3072 private key path."
  [[ -f "$ILO_BOARD_FIRMWARE_SIGNING_KEY" ]] || fail "Firmware signing key does not exist."
  local private_path
  private_path="${ILO_BOARD_FIRMWARE_SIGNING_KEY:A}"
  [[ "$private_path" != "$ILO_BOARD_ROOT"/* ]] || fail "The firmware private key must live outside this repository."
  [[ "${ILO_BOARD_FIRMWARE_PUBLIC_KEY:A}" != "$private_path" ]] || fail "Public and private key paths must be different."
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

appcast_path() {
  print -- "$ILO_BOARD_ARTIFACTS_DIR/appcast.xml"
}

public_versioned_dmg_uri() {
  print -- "$ILO_BOARD_PUBLIC_VERSIONED_RELEASES_URI/$(release_basename).dmg"
}

public_versioned_dmg_url() {
  print -- "$ILO_BOARD_PUBLIC_VERSIONED_RELEASES_URL/$(release_basename).dmg"
}

require_signing_identity() {
  [[ -n "${ILO_BOARD_SIGNING_IDENTITY:-}" ]] || fail "Set ILO_BOARD_SIGNING_IDENTITY in Config/release.env."
  security find-identity -v -p codesigning | grep -Fq "\"$ILO_BOARD_SIGNING_IDENTITY\"" || fail "Signing identity is not available in this Keychain: $ILO_BOARD_SIGNING_IDENTITY"
}

require_notary_profile() {
  [[ -n "${ILO_BOARD_NOTARY_PROFILE:-}" ]] || fail "Set ILO_BOARD_NOTARY_PROFILE in Config/release.env."
}

require_sparkle_public_key() {
  [[ -n "${ILO_BOARD_SPARKLE_PUBLIC_ED_KEY:-}" ]] || fail "Set ILO_BOARD_SPARKLE_PUBLIC_ED_KEY in Config/release.env after running make sparkle-generate-keys."
}

sparkle_tool_path() {
  local tool_name="$1"
  local configured="${ILO_BOARD_SPARKLE_TOOLS_DIR:-}"
  local candidate

  if [[ -n "$configured" ]]; then
    candidate="$configured/$tool_name"
    [[ -x "$candidate" ]] || fail "Sparkle tool is not executable: $candidate"
    print -- "$candidate"
    return
  fi

  local -a candidates=(
    "$ILO_BOARD_PACKAGE/.build/artifacts/sparkle/Sparkle/bin/$tool_name"(N)
    "$ILO_BOARD_ARTIFACTS_DIR/swift-build/arm64/artifacts/sparkle/Sparkle/bin/$tool_name"(N)
    "$ILO_BOARD_ARTIFACTS_DIR/swift-build/x86_64/artifacts/sparkle/Sparkle/bin/$tool_name"(N)
  )
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      print -- "$candidate"
      return
    fi
  done
  fail "Sparkle $tool_name was not found. Run make mac-build first or set ILO_BOARD_SPARKLE_TOOLS_DIR."
}

validate_sparkle_configuration() {
  local app_path="$1"
  local info="$app_path/Contents/Info.plist"
  local feed public_key
  [[ -f "$info" ]] || fail "Info.plist not found: $info"
  feed="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info" 2>/dev/null || true)"
  public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info" 2>/dev/null || true)"
  [[ "$feed" == https://* ]] || fail "Sparkle feed must be an HTTPS URL."
  [[ -n "$public_key" ]] || fail "Packaged app is missing SUPublicEDKey."
}

sign_sparkle_framework() {
  local app_path="$1"
  local identity="$2"
  local framework="$app_path/Contents/Frameworks/Sparkle.framework"
  local -a sign_args=(--force --options runtime --sign "$identity")

  [[ -d "$framework" ]] || fail "Sparkle.framework is missing from the app bundle."
  if [[ "$identity" != "-" ]]; then
    sign_args+=(--timestamp)
  fi

  local installer="$framework/Versions/B/XPCServices/Installer.xpc"
  local downloader="$framework/Versions/B/XPCServices/Downloader.xpc"
  local autoupdate="$framework/Versions/B/Autoupdate"
  local updater="$framework/Versions/B/Updater.app"

  [[ ! -e "$installer" ]] || codesign "${sign_args[@]}" "$installer"
  [[ ! -e "$downloader" ]] || codesign "${sign_args[@]}" --preserve-metadata=entitlements "$downloader"
  codesign "${sign_args[@]}" "$autoupdate"
  codesign "${sign_args[@]}" "$updater"
  codesign "${sign_args[@]}" "$framework"
}

ensure_clean_worktree() {
  git diff --quiet || fail "Working tree has unstaged changes."
  git diff --cached --quiet || fail "Index has staged but uncommitted changes."
  [[ -z "$(git ls-files --others --exclude-standard)" ]] || fail "Working tree has untracked files."
}

current_branch() {
  local branch
  branch="$(git branch --show-current)"
  [[ -n "$branch" ]] || fail "Detached HEAD is not supported for releases."
  print -- "$branch"
}

version_tag() {
  print -- "v$ILO_BOARD_MARKETING_VERSION"
}
