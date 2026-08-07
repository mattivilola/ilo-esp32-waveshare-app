.PHONY: doctor firmware-setup firmware-build firmware-flash firmware-monitor mac-build mac-test mac-run test

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

mac-build:
	cd mac-service && swift build

mac-test:
	cd mac-service && swift test

mac-run:
	cd mac-service && swift run ilo-board-host serve --mock

test: mac-test

