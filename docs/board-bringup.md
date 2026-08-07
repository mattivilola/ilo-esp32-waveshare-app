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

If automatic download fails, hold BOOT, tap RESET, release BOOT, and retry. Waveshare also documents holding BOOT while reconnecting USB. Press RESET once after a successful first download if the app does not start automatically.

## Recovery

The CLI's erase and restore operations require explicit confirmation text. A normal build or flash never erases the entire chip.

Official references:

- [Waveshare board documentation](https://docs.waveshare.com/ESP32-S3-Touch-LCD-5)
- [Waveshare ESP-IDF setup](https://docs.waveshare.com/ESP32-S3-Touch-LCD-5/Development-Environment-Setup-ESP-IDF)
- [Waveshare hardware resources, schematic, and component datasheets](https://docs.waveshare.com/ESP32-S3-Touch-LCD-5/Resources-And-Documents)
- [Espressif serial connection guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32s3/get-started/establish-serial-connection.html)
