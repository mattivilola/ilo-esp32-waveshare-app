#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command swift
ensure_command lipo
ensure_command codesign
ensure_command ditto
ensure_command install_name_tool

mkdir -p "$ILO_BOARD_ARTIFACTS_DIR"
app_path="$(release_app_path)"
build_root="$ILO_BOARD_ARTIFACTS_DIR/swift-build"
arm_root="$build_root/arm64"
x86_root="$build_root/x86_64"

rm -rf "$app_path"

swift build --package-path "$ILO_BOARD_PACKAGE" --configuration release --arch arm64 --scratch-path "$arm_root" --product "$ILO_BOARD_EXECUTABLE"
swift build --package-path "$ILO_BOARD_PACKAGE" --configuration release --arch x86_64 --scratch-path "$x86_root" --product "$ILO_BOARD_EXECUTABLE"

arm_bin_dir="$(swift build --package-path "$ILO_BOARD_PACKAGE" --configuration release --arch arm64 --scratch-path "$arm_root" --show-bin-path)"
x86_bin_dir="$(swift build --package-path "$ILO_BOARD_PACKAGE" --configuration release --arch x86_64 --scratch-path "$x86_root" --show-bin-path)"
arm_binary="$arm_bin_dir/$ILO_BOARD_EXECUTABLE"
x86_binary="$x86_bin_dir/$ILO_BOARD_EXECUTABLE"
[[ -x "$arm_binary" && -x "$x86_binary" ]] || fail "SwiftPM did not produce both architecture binaries."
[[ -d "$arm_bin_dir/Sparkle.framework" ]] || fail "SwiftPM did not produce Sparkle.framework."
sparkle_license="$arm_root/artifacts/sparkle/Sparkle/LICENSE"
[[ -f "$sparkle_license" ]] || fail "Sparkle license was not found in the resolved binary artifact."

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Frameworks"
cp "$ILO_BOARD_ROOT/Packaging/Info.plist" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $ILO_BOARD_MARKETING_VERSION" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $ILO_BOARD_BUILD_NUMBER" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ILO_BOARD_BUNDLE_ID" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL $ILO_BOARD_PUBLIC_APPCAST_URL" "$app_path/Contents/Info.plist"
if [[ -n "${ILO_BOARD_SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $ILO_BOARD_SPARKLE_PUBLIC_ED_KEY" "$app_path/Contents/Info.plist"
fi

lipo -create "$arm_binary" "$x86_binary" -output "$app_path/Contents/MacOS/$ILO_BOARD_EXECUTABLE"
chmod +x "$app_path/Contents/MacOS/$ILO_BOARD_EXECUTABLE"
ditto "$arm_bin_dir/Sparkle.framework" "$app_path/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$app_path/Contents/MacOS/$ILO_BOARD_EXECUTABLE" 2>/dev/null || true
"$ILO_BOARD_ROOT/scripts/build_icon.sh" "$app_path/Contents/Resources/AppIcon.icns"
cp "$ILO_BOARD_PACKAGE/Sources/ILOBoardMenu/Resources/icon_round.png" "$app_path/Contents/Resources/icon_round.png"
cp "$sparkle_license" "$app_path/Contents/Resources/Sparkle-LICENSE.txt"

sign_sparkle_framework "$app_path" -
codesign --force --options runtime --entitlements "$ILO_BOARD_ROOT/Packaging/Debug.entitlements" --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
log "Built universal app bundle at $app_path"
