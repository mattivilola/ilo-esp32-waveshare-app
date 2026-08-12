# OTA update and recovery policy

OTA delivery is built as a fail-closed release path. The normal developer build still has no network installer. Only the dedicated signed release profile may contain the updater, and publishing remains a separate explicit command.

## What is implemented

- `firmware/partitions.csv` contains equal 4 MiB `ota_0` and `ota_1` slots plus `otadata`; factory/test app partitions are forbidden by the CLI policy check.
- Clean firmware builds enable ESP-IDF application rollback.
- A new image remains `ESP_OTA_IMG_PENDING_VERIFY` after boot. The firmware checks the slot layout, completes board/display/UI initialization, waits 30 stable seconds, checks free internal heap, rechecks its partition state, and only then marks the image valid.
- A failed health check requests rollback when a previous valid image exists. The first USB bridge has no previous OTA image, so it still runs the same health window and becomes valid only on success; on failure it remains unconfirmed and USB recovery is required.
- `./tools/board ota-status [--sdkconfig FILE]` inspects policy without hardware.
- `./tools/board ota-verify --image FILE.bin --public-key PUBLIC.pem --sdkconfig FILE` fail-closes unless the artifact fits a slot, is a valid ESP image, was built with rollback and signed-update enforcement, and carries a valid RSA Secure Boot v2 signature. It refuses PEM private keys and never uploads.
- `protocol/firmware-manifest-v1.schema.json` defines the small signed-envelope boundary. `tools/firmware_manifest.py` creates and verifies the stricter executable contract.

## Signed manifest v1

The outer JSON envelope contains only `schema`, `algorithm`, `keyID`, a canonical JSON payload encoded as base64, and an RSA-PSS-SHA256 signature. Signing the exact payload bytes avoids ambiguous JSON canonicalization on the ESP32. The verifier rejects unknown fields, non-canonical base64 or JSON, weak/wrong keys, and malformed signatures.

The signed payload binds all security-relevant metadata:

- exact hardware target `waveshare-esp32-s3-touch-lcd-5b-28151`;
- stable channel, semantic version, and monotonically increasing release sequence;
- publication time and minimum updater version;
- exact immutable GCS HTTPS artifact URL, byte size, and lowercase SHA-256;
- one to eight bounded release-note strings.

The mutable manifest is intentionally published last. The versioned binary is created with GCS `--if-generation-match=0`, downloaded again, and compared byte-for-byte before the manifest may change. A client therefore cannot discover a signed manifest for an unavailable or different artifact.

## Signing boundary

`firmware/sdkconfig.ota-release.defaults` enables ESP-IDF signed-application verification without enabling hardware Secure Boot. It intentionally disables build-time signing: the output must be signed by an external/offline RSA-3072 key and verified with its public key. A production private key must never be generated in or copied into this repository, shell history, CI logs, a GCS bucket, the Mac app, or the ESP32.

Software-only signed updates protect a future network delivery path but do not stop a person with physical flash access from replacing the bootloader. Hardware Secure Boot v2, flash encryption, and anti-rollback eFuses are stronger but irreversible. Their key ceremony and first-device provisioning require separate approval, backups, documented recovery, and physical testing; this project does not burn eFuses automatically.

## Release commands

1. Run `make firmware-key-create` once. It uses hidden macOS dialogs to create a password-encrypted PKCS#8 RSA-3072 private PEM outside the repository plus its public PEM and checksums. Back up the encrypted PEM and checksum to a separate encrypted/offline device before the first bridge flash. Put only their paths and release metadata in ignored `Config/release.env`; the private key must stay outside the repository and GCS.
2. Set a strictly increasing `ILO_BOARD_FIRMWARE_RELEASE_SEQUENCE` and bounded release notes.
3. Run `make firmware-release-local`. It asks for the key passphrase, decrypts only into a mode-`600` session directory, builds with both sdkconfig defaults files, externally signs the ESP image, verifies the image signature, creates the manifest, verifies the manifest, and removes the temporary plaintext key on exit. It changes neither GCS nor a board.
4. Inspect the versioned files under `artifacts/firmware/VERSION/`.
5. For the one-time bridge, run `make firmware-release-flash PORT=/dev/cu...`. It needs only the public verification key, re-verifies the signed release, and writes bootloader, partition table, OTA metadata, and the signed app while deliberately preserving NVS at `0x9000` (Wi-Fi, pairing, weather, and device settings). It never builds or signs during flash.
6. Run `make firmware-release-distribute` explicitly. It also needs only the public verification key, repeats all local checks, refuses an existing immutable object, enforces a sequence newer than the published signed manifest, verifies the uploaded binary, and publishes the manifest last.

The manifest and ESP image currently use the same controlled RSA-3072 key so there is one durable trust decision. This is domain-separated by file format and verification path. The public key is safe to embed and distribute; the private key is not.

## Device and companion behavior

The release build checks automatically after Wi-Fi becomes available; it never installs automatically. Settings shows `CHECK`, `CHECKING`, `UP TO DATE`, `INSTALL VERSION`, progress, verification, reboot, or a retry state. The Mac companion mirrors those bounded states and offers the same explicit actions while connected. Its request contains no URL or artifact metadata. The board always refetches and verifies its compiled manifest origin itself, so the board also works independently when the Mac is absent.

Download writes only the inactive OTA slot. The active boot selection is changed only after the exact content length and SHA-256 match, `esp_ota_end` accepts the signed ESP image, and its embedded project/version metadata matches the signed manifest. An interruption during download therefore leaves the old slot selected. On first boot, interruption before confirmation causes ESP-IDF rollback to the last valid slot.

## Remaining gates

- Prove the 30-second confirmation, crash rollback, partial-write recovery, NVS preservation, and repeated A/B slot cycling on hardware.
- Establish offline/HSM key custody, public-key distribution, incident recovery, and audit records. Software-only signed updates accept only the first signature block, so changing this trust root requires another deliberate USB bridge flash.
- Decide rollout cohorts and rate limits after the first-device physical gates pass.
- Decide whether production devices require irreversible hardware Secure Boot, flash encryption, and eFuse anti-rollback.
- Write the step-by-step USB recovery runbook after the first physical fault-injection session confirms the exact operator-visible behavior.
