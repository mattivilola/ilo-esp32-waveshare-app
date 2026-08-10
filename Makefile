SHELL := /bin/zsh

.PHONY: help doctor firmware-setup firmware-build firmware-flash firmware-monitor ui-preview ui-screenshots mac-build mac-test mac-run mac-menu app package-dmg sign-release notarize staple release-local release-distribute test

help:
	@printf "ILO Board commands\n\n"
	@printf "  make doctor              Check board and Mac development prerequisites\n"
	@printf "  make firmware-setup      Install the pinned ESP-IDF toolchain\n"
	@printf "  make firmware-build      Compile firmware without hardware\n"
	@printf "  make firmware-flash      Flash a connected Waveshare 5B\n"
	@printf "  make firmware-monitor    Open the board serial monitor\n"
	@printf "  make ui-preview          Open the desktop 1024x600 device UI preview\n"
	@printf "  make ui-screenshots      Export PNG previews for all four device screens\n"
	@printf "  make mac-build           Build the Swift package\n"
	@printf "  make mac-test            Run all macOS host tests\n"
	@printf "  make mac-menu            Run the menu-bar app from SwiftPM\n"
	@printf "  make app                 Build a universal macOS .app bundle\n"
	@printf "  make package-dmg         Package the current .app as a DMG\n"
	@printf "  make sign-release        Developer ID-sign the app and DMG\n"
	@printf "  make notarize            Submit the DMG to Apple notarization\n"
	@printf "  make staple              Staple and validate the notarization ticket\n"
	@printf "  make release-local       Build, sign, package, notarize, and staple\n"
	@printf "  make release-distribute  Upload verified DMGs to the configured GCS bucket\n"
	@printf "  make test                Run all hardware-independent tests\n"

doctor:
	./tools/board doctor

firmware-setup:
	./tools/setup-idf

firmware-build:
	./tools/board build

firmware-flash:
	./tools/board flash

firmware-monitor:
	./tools/board monitor

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

release-local:
	./scripts/release_local.sh

release-distribute:
	./scripts/release_distribute.sh

test: mac-test
	./scripts/test_release_tools.sh
