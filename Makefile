SHELL := /bin/zsh

BOARD_SCREENSHOT_OUTPUT ?= artifacts/board-screenshots/ilo-board-$(shell date +%Y%m%d-%H%M%S).png
BOARD_SCREENSHOT_TIMEOUT ?= 120

.PHONY: help doctor assets versions firmware-version firmware-version-patch firmware-version-minor firmware-setup firmware-build firmware-flash firmware-flash-minor firmware-monitor ota-status firmware-key-create firmware-release-local firmware-release-flash firmware-release-distribute ui-preview ui-screenshots board-screenshot mac-version mac-version-patch mac-version-minor mac-build mac-test mac-run mac-menu app package-dmg sign-release notarize staple sparkle-generate-keys release-version version-patch version-minor version-major release-commit release-tag release-push release-local release-distribute test verify

help:
	@printf "ILO Board commands\n\n"
	@printf "  make doctor              Check board and Mac development prerequisites\n"
	@printf "  make assets              Regenerate macOS and firmware icon assets\n"
	@printf "  make versions            Show Mac companion and firmware versions\n"
	@printf "  make firmware-version    Show the current firmware version\n"
	@printf "  make firmware-version-patch  Bump only the firmware patch version\n"
	@printf "  make firmware-version-minor  Bump only the firmware minor version\n"
	@printf "  make firmware-setup      Install the pinned ESP-IDF toolchain\n"
	@printf "  make firmware-build      Compile firmware without hardware\n"
	@printf "  make firmware-flash      Patch-bump and flash a connected Waveshare 5B\n"
	@printf "  make firmware-flash-minor  Minor-bump and flash a connected Waveshare 5B\n"
	@printf "  make firmware-monitor    Open the board serial monitor\n"
	@printf "  make ota-status          Inspect OTA safety gates without hardware\n"
	@printf "  make firmware-key-create Create encrypted external RSA-3072 OTA key\n"
	@printf "  make firmware-release-local  Build, sign, and verify firmware; never upload\n"
	@printf "  make firmware-release-flash PORT=/dev/cu...  USB-flash verified signed bridge\n"
	@printf "  make firmware-release-distribute  Publish verified firmware and manifest\n"
	@printf "  make ui-preview          Open the desktop 1024x600 device UI preview\n"
	@printf "  make ui-screenshots      Export PNG previews for all five device screens\n"
	@printf "  make board-screenshot    Save the current physical board screen as a PNG\n"
	@printf "  make mac-build           Build the Swift package\n"
	@printf "  make mac-version         Show the Mac companion version and build\n"
	@printf "  make mac-version-patch   Prepare the next Mac companion patch version\n"
	@printf "  make mac-version-minor   Prepare the next Mac companion minor version\n"
	@printf "  make mac-test            Run all macOS host tests\n"
	@printf "  make mac-menu            Run the menu-bar app from SwiftPM\n"
	@printf "  make app                 Build a universal macOS .app bundle\n"
	@printf "  make package-dmg         Package the current .app as a DMG\n"
	@printf "  make sign-release        Developer ID-sign the app and DMG\n"
	@printf "  make notarize            Submit the DMG to Apple notarization\n"
	@printf "  make staple              Staple and validate the notarization ticket\n"
	@printf "  make sparkle-generate-keys  Create/read the Sparkle EdDSA key in Keychain\n"
	@printf "  make release-version     Show the current app version and build\n"
	@printf "  make version-patch       Prepare the next patch version and changelog\n"
	@printf "  make version-minor       Prepare the next minor version and changelog\n"
	@printf "  make version-major       Prepare the next major version and changelog\n"
	@printf "  make release-commit      Commit prepared version and changelog files\n"
	@printf "  make release-tag         Tag the committed current version\n"
	@printf "  make release-push        Push the current branch and release tag\n"
	@printf "  make release-local       Build, sign, package, notarize, and staple\n"
	@printf "  make release-distribute  Upload DMGs and signed Sparkle appcast to GCS\n"
	@printf "  make test                Run all hardware-independent tests\n"
	@printf "  make verify              Run tests plus a complete firmware compile\n"

doctor:
	./tools/board doctor

assets:
	./scripts/build_icon.sh
	./scripts/generate_firmware_icon.sh

versions: mac-version firmware-version

firmware-version:
	./scripts/firmware_version.sh current

firmware-version-patch:
	./scripts/firmware_version.sh bump patch

firmware-version-minor:
	./scripts/firmware_version.sh bump minor

firmware-setup:
	./tools/setup-idf

firmware-build:
	./tools/board build

firmware-flash:
	./tools/board flash

firmware-flash-minor:
	./tools/board flash --version-bump minor

firmware-monitor:
	./tools/board monitor

ota-status:
	./tools/board ota-status

firmware-key-create:
	./scripts/firmware_key_create.sh

firmware-release-local:
	./scripts/firmware_release_local.sh

firmware-release-flash:
	./scripts/firmware_release_flash.sh "$(PORT)"

firmware-release-distribute:
	./scripts/firmware_release_distribute.sh

ui-preview:
	./tools/board ui-preview

ui-screenshots:
	./tools/board ui-screenshot --all

board-screenshot:
	./scripts/capture_board_screenshot.sh "$(BOARD_SCREENSHOT_OUTPUT)" "$(BOARD_SCREENSHOT_TIMEOUT)"

mac-build:
	./tools/host build

mac-test:
	./tools/host test

mac-run:
	./tools/host serve

mac-menu:
	./tools/host menu

mac-version: release-version

mac-version-patch: version-patch

mac-version-minor: version-minor

app:
	./scripts/build_app.sh

package-dmg: app
	./scripts/package_dmg.sh

sign-release:
	./scripts/sign_release.sh

notarize:
	./scripts/notarize.sh

staple:
	./scripts/staple.sh

sparkle-generate-keys: mac-build
	./scripts/sparkle_keys.sh

release-version:
	./scripts/version.sh current

version-patch:
	./scripts/version.sh bump patch

version-minor:
	./scripts/version.sh bump minor

version-major:
	./scripts/version.sh bump major

release-commit:
	./scripts/release_commit.sh

release-tag:
	./scripts/release_tag.sh

release-push:
	./scripts/release_push.sh

release-local:
	./scripts/release_local.sh

release-distribute:
	./scripts/release_distribute.sh

test: mac-test
	python3 -m unittest discover -s tests
	./scripts/test_release_tools.sh

verify: test firmware-build
