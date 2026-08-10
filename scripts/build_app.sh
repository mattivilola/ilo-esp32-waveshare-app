#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
ensure_command swift
ensure_command lipo
ensure_command codesign
ensure_command ditto

mkdir -p "$ILO_BOARD_ARTIFACTS_DIR"
app_path="$(release_app_path)"
build_root="$ILO_BOARD_ARTIFACTS_DIR/swift-build"
arm_root="$build_root/arm64"
x86_root="$build_root/x86_64"

rm -rf "$app_path"

swift build --package-path "$ILO_BOARD_PACKAGE" --configuration release --arch arm64 --scratch-path "$arm_root" --product "$ILO_BOARD_EXECUTABLE"
swift build --package-path "$ILO_BOARD_PACKAGE" --configuration release --arch x86_64 --scratch-path "$x86_root" --product "$ILO_BOARD_EXECUTABLE"

arm_binary="$(swift build --package-path "$ILO_BOARD_PACKAGE" --configuration release --arch arm64 --scratch-path "$arm_root" --show-bin-path)/$ILO_BOARD_EXECUTABLE"
x86_binary="$(swift build --package-path "$ILO_BOARD_PACKAGE" --configuration release --arch x86_64 --scratch-path "$x86_root" --show-bin-path)/$ILO_BOARD_EXECUTABLE"
[[ -x "$arm_binary" && -x "$x86_binary" ]] || fail "SwiftPM did not produce both architecture binaries."

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$ILO_BOARD_ROOT/Packaging/Info.plist" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $ILO_BOARD_MARKETING_VERSION" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $ILO_BOARD_BUILD_NUMBER" "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ILO_BOARD_BUNDLE_ID" "$app_path/Contents/Info.plist"

lipo -create "$arm_binary" "$x86_binary" -output "$app_path/Contents/MacOS/$ILO_BOARD_EXECUTABLE"
chmod +x "$app_path/Contents/MacOS/$ILO_BOARD_EXECUTABLE"
"$ILO_BOARD_ROOT/scripts/build_icon.sh" "$app_path/Contents/Resources/AppIcon.icns"
cp "$ILO_BOARD_PACKAGE/Sources/ILOBoardMenu/Resources/icon_round.png" "$app_path/Contents/Resources/icon_round.png"

codesign --force --options runtime --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
log "Built universal app bundle at $app_path"
