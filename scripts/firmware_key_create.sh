#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/firmware_key.sh"

ensure_command openssl
key_dir="${ILO_BOARD_FIRMWARE_KEY_DIR:-$HOME/Library/Application Support/ILO Board/Firmware Signing}"
private_key="$key_dir/ilo-board-firmware-rsa3072-encrypted.pem"
public_key="$key_dir/ilo-board-firmware-rsa3072-public.pem"
checksums="$key_dir/SHA256SUMS"

[[ ! -e "$private_key" && ! -e "$public_key" && ! -e "$checksums" ]] \
  || fail "Firmware key material already exists at the configured destination; refusing to replace it."

umask 077
mkdir -p "$key_dir"
passphrase="$(firmware_key_new_passphrase_dialog)" || fail "Firmware key creation was cancelled."
print -r -- "$passphrase" | openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:3072 \
  -aes-256-cbc \
  -pass stdin \
  -out "$private_key" >/dev/null 2>&1 \
  || fail "Encrypted RSA-3072 key generation failed."
print -r -- "$passphrase" | openssl pkey \
  -in "$private_key" \
  -passin stdin \
  -pubout \
  -out "$public_key" >/dev/null 2>&1 \
  || fail "Firmware public-key derivation failed."
unset passphrase

firmware_key_is_encrypted "$private_key" || fail "Generated private key is not encrypted PKCS#8 PEM."
openssl pkey -pubin -in "$public_key" -text -noout 2>/dev/null \
  | grep -Fq 'Public-Key: (3072 bit)' \
  || fail "Generated firmware public key is not RSA-3072."
(
  cd "$key_dir"
  shasum -a 256 "${private_key:t}" "${public_key:t}" > "${checksums:t}"
)
chmod 600 "$private_key" "$public_key" "$checksums"

log "Created an encrypted RSA-3072 firmware signing key."
log "Private key: $private_key"
log "Public key:  $public_key"
log "Checksum:    $checksums"
log "Back up the encrypted private PEM and checksum to a separate encrypted/offline device before the first bridge flash."
