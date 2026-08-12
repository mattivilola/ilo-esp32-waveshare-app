#!/bin/zsh

firmware_key_passphrase_dialog() {
  local prompt_title="${1:-ILO Board firmware signing key}"
  /usr/bin/osascript <<APPLESCRIPT
set secretText to text returned of (display dialog "Enter the firmware signing-key passphrase. It is used only for this local operation and is not stored." default answer "" with hidden answer buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel" with title "$prompt_title")
if length of secretText < 14 then error "Use at least 14 characters for the firmware signing-key passphrase."
return secretText
APPLESCRIPT
}

firmware_key_new_passphrase_dialog() {
  local first second
  first="$(firmware_key_passphrase_dialog "Create ILO Board firmware key")" || return 1
  second="$(/usr/bin/osascript <<'APPLESCRIPT'
set secretText to text returned of (display dialog "Confirm the new firmware signing-key passphrase." default answer "" with hidden answer buttons {"Cancel", "Create Key"} default button "Create Key" cancel button "Cancel" with title "Create ILO Board firmware key")
return secretText
APPLESCRIPT
)" || return 1
  [[ "$first" == "$second" ]] || fail "Passphrases did not match; no key was created."
  print -rn -- "$first"
}

firmware_key_is_encrypted() {
  grep -Fq -- '-----BEGIN ENCRYPTED PRIVATE KEY-----' "$1"
}

unlock_firmware_signing_key() {
  local encrypted_key="$1"
  local output="$2"
  local passphrase
  firmware_key_is_encrypted "$encrypted_key" || fail "Firmware signing key is not an encrypted PKCS#8 PEM."
  passphrase="$(firmware_key_passphrase_dialog "Unlock ILO Board firmware key")" || fail "Firmware key unlock was cancelled."
  umask 077
  print -r -- "$passphrase" | openssl pkey \
    -in "$encrypted_key" \
    -passin stdin \
    -out "$output" >/dev/null 2>&1 \
    || fail "Firmware signing key could not be unlocked."
  unset passphrase
  chmod 600 "$output"
  openssl pkey -in "$output" -check -noout >/dev/null 2>&1 \
    || fail "Unlocked firmware signing key is invalid."
}
