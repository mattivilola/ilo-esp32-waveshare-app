# OTA update and recovery policy

This is a safety foundation, not an enabled remote updater. No command in this repository uploads an image, changes OTA data, contacts an update server, or writes a live board over Wi-Fi.

## What is implemented

- `firmware/partitions.csv` contains equal 4 MiB `ota_0` and `ota_1` slots plus `otadata`; factory/test app partitions are forbidden by the CLI policy check.
- Clean firmware builds enable ESP-IDF application rollback.
- A new image remains `ESP_OTA_IMG_PENDING_VERIFY` after boot. The firmware checks the slot layout, completes board/display/UI initialization, waits 30 stable seconds, checks free internal heap, rechecks its partition state, and only then marks the image valid.
- A failed health check requests rollback when a previous valid image exists. With no recovery image, the candidate remains unconfirmed and USB recovery is required.
- `./tools/board ota-status [--sdkconfig FILE]` inspects policy without hardware.
- `./tools/board ota-verify --image FILE.bin --public-key PUBLIC.pem --sdkconfig FILE` fail-closes unless the artifact fits a slot, is a valid ESP image, was built with rollback and signed-update enforcement, and carries a valid RSA Secure Boot v2 signature. It refuses PEM private keys and never uploads.

## Signing boundary

`firmware/sdkconfig.ota-release.defaults` enables ESP-IDF signed-application verification without enabling hardware Secure Boot. It intentionally disables build-time signing: the output must be signed by an external/offline RSA-3072 key and verified with its public key. A production private key must never be generated in or copied into this repository, shell history, CI logs, a GCS bucket, the Mac app, or the ESP32.

Software-only signed updates protect a future network delivery path but do not stop a person with physical flash access from replacing the bootloader. Hardware Secure Boot v2, flash encryption, and anti-rollback eFuses are stronger but irreversible. Their key ceremony and first-device provisioning require separate approval, backups, documented recovery, and physical testing; this project does not burn eFuses automatically.

## Release sequence once keys and hosting exist

1. Build in an isolated directory using `sdkconfig.defaults` plus `sdkconfig.ota-release.defaults`.
2. Sign the application outside the repository with the controlled RSA-3072 private key or HSM.
3. Run `ota-verify` with the public key and the generated release sdkconfig. Record the SHA-256 it prints.
4. Publish only the verified signed binary and an authenticated manifest over HTTPS. Publishing and device installation commands do not exist yet.
5. Exercise HW-411 and HW-412 on a sacrificial 5B before enabling delivery for any other board.

## Remaining gates

- Prove the 30-second confirmation, crash rollback, partial-write recovery, NVS preservation, and repeated A/B slot cycling on hardware.
- Choose authenticated manifest format, pinned trust/update origin, rollout cohorts, rate limits, and revocation policy.
- Establish offline/HSM key custody, public-key distribution, rotation, incident recovery, and audit records.
- Decide whether production devices require irreversible hardware Secure Boot, flash encryption, and eFuse anti-rollback.
- Add a user-visible update state and explicit local recovery instructions before any automatic check or install path.
