# Board bring-up

Target: Waveshare ESP32-S3-Touch-LCD-5B, SKU 28151, 1024×600. The purchased Amazon ASIN B0DD7N19FT identifies this exact 5B variant; the no-suffix 800×480 profile must not be flashed.

Reference purchase: [Waveshare ESP32-S3-Touch-LCD-5B on Amazon.de](https://www.amazon.de/dp/B0DD7N19FT).

The firmware profile uses the 5B-specific 21 MHz pixel clock and 1024×600 RGB timings. Shared family features—ESP32-S3-WROOM-1-N16R8, GT911 touch, and CH422G-controlled reset/backlight—do not make the 800×480 firmware interchangeable.

## Physical connection

1. Leave any battery switch off while debugging over USB.
2. Connect the board directly with a data-capable USB-C cable.
3. The board powers immediately; there is no separate power-on step for USB use.
4. Keep metal away from the PCB antenna area.

Expected macOS identity:

```text
USB JTAG/serial debug unit
Vendor 0x303a (Espressif)
/dev/cu.usbmodem*
```

Run `./tools/board doctor` and `./tools/board chip-id`. The CLI discovers ports; it does not hard-code a device suffix.

## Factory backup

Before first flash:

```bash
./tools/board backup
```

Backups are written to ignored `artifacts/factory-backups/`. Keep at least one verified 16 MB image somewhere safe.

## Build and flash

```bash
./tools/setup-idf
./tools/board build
./tools/board flash
./tools/board monitor
```

Exit the monitor with `Ctrl-]`.

If automatic download fails, hold BOOT, press and release RESET while continuing to hold BOOT, then release BOOT and retry. Waveshare also documents holding BOOT while reconnecting USB.

After a successful flash, a serial log of `DOWNLOAD(USB/UART0)` plus `waiting for download` means the ROM loader is still active. Press and release RESET once only, without BOOT, to start the application. This does not erase or reflash the board.

## Secure Wi-Fi provisioning

Provisioning is separate from the firmware build, so the same binary can be shared without embedding network credentials:

```bash
./tools/board provision
```

The command:

1. reads the SSID, a hidden Wi-Fi password, Mac LAN address, and service port interactively;
2. creates a per-board opaque ID and random 32-byte PSK;
3. stores the PSK in the signed-in user's macOS Keychain;
4. generates a temporary NVS image outside the repository;
5. asks for the documented BOOT/RESET download-mode sequence;
6. writes and verifies only the `nvs` partition at the offset declared in `firmware/partitions.csv`;
7. removes its temporary secret material automatically.

After provisioning succeeds, press and release RESET once without BOOT. Start the menu-bar host with `./tools/host menu`. Re-run provisioning when the Wi-Fi network or Mac LAN address changes. Replacing this Phase-1 direct-address fallback with firmware-side Bonjour discovery is the next transport increment.

Verified success appears in the Mac menu as `ONLINE`, `Board connected`, and a current `Last sync` value. Those states are emitted only after the ESP32 completes TLS-PSK authentication and begins receiving recurring snapshots. The first physical 5B handshake was verified on port `47472`; no board ID, IP address, Wi-Fi credential, or PSK belongs in Git or screenshots intended for publication.

## Recovery

The CLI's erase and restore operations require explicit confirmation text. A normal build or flash never erases the entire chip.

Official references:

- [Waveshare board documentation](https://docs.waveshare.com/ESP32-S3-Touch-LCD-5)
- [Waveshare ESP-IDF setup](https://docs.waveshare.com/ESP32-S3-Touch-LCD-5/Development-Environment-Setup-ESP-IDF)
- [Waveshare hardware resources, schematic, and component datasheets](https://docs.waveshare.com/ESP32-S3-Touch-LCD-5/Resources-And-Documents)
- [Espressif serial connection guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/get-started/establish-serial-connection.html)
