SHELL := /bin/zsh

.PHONY: help doctor assets firmware-setup firmware-build firmware-flash firmware-monitor ota-status ui-preview ui-screenshots mac-build mac-test mac-run mac-menu app package-dmg sign-release notarize staple sparkle-generate-keys release-version version-patch version-minor version-major release-commit release-tag release-push release-local release-distribute test verify

help:
	@printf "ILO Board commands\n\n"
	@printf "  make doctor              Check board and Mac development prerequisites\n"
	@printf "  make assets              Regenerate macOS and firmware icon assets\n"
	@printf "  make firmware-setup      Install the pinned ESP-IDF toolchain\n"
	@printf "  make firmware-build      Compile firmware without hardware\n"
	@printf "  make firmware-flash      Flash a connected Waveshare 5B\n"
	@printf "  make firmware-monitor    Open the board serial monitor\n"
	@printf "  make ota-status          Inspect OTA safety gates without hardware\n"
	@printf "  make ui-preview          Open the desktop 1024x600 device UI preview\n"
	@printf "  make ui-screenshots      Export PNG previews for all five device screens\n"
	@printf "  make mac-build           Build the Swift package\n"
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

firmware-setup:
	./tools/setup-idf

firmware-build:
	./tools/board build

firmware-flash:
	./tools/board flash

firmware-monitor:
	./tools/board monitor

ota-status:
	./tools/board ota-status

ui-preview:
	./tools/board ui-preview

ui-screenshots:
	./tools/board ui-screenshot --all

mac-build:
	./tools/host build

mac-test:
	./tools/host test

mac-run:
	./tools/host serve

mac-menu:
	./tools/host menu

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
