.PHONY: doctor firmware-setup firmware-build firmware-flash firmware-monitor mac-build mac-test mac-run mac-menu test

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
	./tools/host build

mac-test:
	./tools/host test

mac-run:
	./tools/host serve

mac-menu:
	./tools/host menu

test: mac-test
