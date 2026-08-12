#!/usr/bin/env python3
"""Create and verify the signed ILO Board firmware manifest envelope."""

from __future__ import annotations

import argparse
import base64
import binascii
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from typing import Any


ENVELOPE_SCHEMA = "ilo-board-firmware-manifest-envelope-v1"
PAYLOAD_SCHEMA = "ilo-board-firmware-manifest-v1"
ALGORITHM = "RSA-PSS-SHA256"
BOARD_TARGET = "waveshare-esp32-s3-touch-lcd-5b-28151"
RELEASE_URL_PREFIX = "https://storage.googleapis.com/ilo-public/ilo-board/firmware/releases/"
MAX_MANIFEST_BYTES = 16_384
MAX_PAYLOAD_BYTES = 8_192
MAX_IMAGE_BYTES = 0x400000
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
KEY_ID = re.compile(r"^[a-f0-9]{16}$")
SHA256 = re.compile(r"^[a-f0-9]{64}$")


class ManifestError(ValueError):
    pass


def _run(command: list[str], *, input_data: bytes | None = None) -> bytes:
    try:
        result = subprocess.run(command, input=input_data, capture_output=True, check=False)
    except FileNotFoundError as error:
        raise ManifestError(f"Required command is unavailable: {command[0]}") from error
    if result.returncode != 0:
        raise ManifestError("Cryptographic operation failed; manifest was not accepted.")
    return result.stdout


def _public_der(public_key: Path) -> bytes:
    if not public_key.is_file():
        raise ManifestError("Manifest public key does not exist.")
    key_data = public_key.read_bytes()
    if b"PRIVATE KEY" in key_data:
        raise ManifestError("Refusing a private key where a public key is required.")
    der = _run(["openssl", "pkey", "-pubin", "-in", str(public_key), "-pubout", "-outform", "DER"])
    details = _run(["openssl", "pkey", "-pubin", "-in", str(public_key), "-text", "-noout"])
    if b"Public-Key: (3072 bit)" not in details:
        raise ManifestError("Manifest verification key must be RSA-3072.")
    return der


def public_key_id(public_key: Path) -> str:
    return hashlib.sha256(_public_der(public_key)).hexdigest()[:16]


def derive_public_key(private_key: Path, output: Path) -> None:
    if not private_key.is_file():
        raise ManifestError("Firmware signing key does not exist.")
    _run(["openssl", "pkey", "-in", str(private_key), "-check", "-noout"])
    public_pem = _run(["openssl", "pkey", "-in", str(private_key), "-pubout"])
    output.write_bytes(public_pem)
    _public_der(output)


def canonical_payload(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")


def _decode_base64(value: Any, field: str, maximum: int) -> bytes:
    if not isinstance(value, str):
        raise ManifestError(f"{field} must be base64 text.")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as error:
        raise ManifestError(f"{field} is not canonical base64.") from error
    if not decoded or len(decoded) > maximum or base64.b64encode(decoded).decode("ascii") != value:
        raise ManifestError(f"{field} has an invalid encoded length.")
    return decoded


def _exact_keys(value: dict[str, Any], expected: set[str], name: str) -> None:
    if set(value) != expected:
        raise ManifestError(f"{name} has missing or unknown fields.")


def validate_payload(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ManifestError("Manifest payload must be an object.")
    _exact_keys(payload, {
        "schema", "target", "channel", "version", "sequence", "publishedAt",
        "minimumUpdaterVersion", "artifact", "releaseNotes",
    }, "Manifest payload")
    if payload["schema"] != PAYLOAD_SCHEMA or payload["target"] != BOARD_TARGET or payload["channel"] != "stable":
        raise ManifestError("Manifest schema, board target, or channel is unsupported.")
    version = payload["version"]
    minimum = payload["minimumUpdaterVersion"]
    if not isinstance(version, str) or SEMVER.fullmatch(version) is None:
        raise ManifestError("Manifest version must be strict semantic version text.")
    if not isinstance(minimum, str) or SEMVER.fullmatch(minimum) is None:
        raise ManifestError("Minimum updater version must be strict semantic version text.")
    sequence = payload["sequence"]
    if not isinstance(sequence, int) or isinstance(sequence, bool) or sequence < 1 or sequence > 2_147_483_647:
        raise ManifestError("Manifest sequence must be a positive 32-bit integer.")
    published = payload["publishedAt"]
    if not isinstance(published, str) or re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", published) is None:
        raise ManifestError("publishedAt must be a whole-second UTC timestamp.")
    try:
        dt.datetime.strptime(published, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise ManifestError("publishedAt is not a real UTC timestamp.") from error

    artifact = payload["artifact"]
    if not isinstance(artifact, dict):
        raise ManifestError("Manifest artifact must be an object.")
    _exact_keys(artifact, {"url", "size", "sha256"}, "Manifest artifact")
    expected_url = f"{RELEASE_URL_PREFIX}ILOBoardFirmware-{version}.bin"
    if artifact["url"] != expected_url:
        raise ManifestError("Artifact URL must be the immutable versioned GCS release URL.")
    size = artifact["size"]
    if not isinstance(size, int) or isinstance(size, bool) or size < 1 or size > MAX_IMAGE_BYTES:
        raise ManifestError("Artifact size does not fit the 4 MiB OTA slot.")
    if not isinstance(artifact["sha256"], str) or SHA256.fullmatch(artifact["sha256"]) is None:
        raise ManifestError("Artifact SHA-256 must be 64 lowercase hexadecimal characters.")

    notes = payload["releaseNotes"]
    if not isinstance(notes, list) or not 1 <= len(notes) <= 8:
        raise ManifestError("Release notes must contain between one and eight items.")
    for note in notes:
        if not isinstance(note, str) or not 1 <= len(note) <= 180 or any(ord(char) < 0x20 for char in note):
            raise ManifestError("Release note text is empty, too long, or contains controls.")
    return payload


def load_and_validate_envelope(path: Path, public_key: Path, *, verify_signature: bool = True) -> dict[str, Any]:
    if not path.is_file() or path.stat().st_size > MAX_MANIFEST_BYTES:
        raise ManifestError("Manifest is missing, empty, or too large.")
    try:
        envelope = json.loads(path.read_bytes())
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise ManifestError("Manifest envelope is not valid UTF-8 JSON.") from error
    if not isinstance(envelope, dict):
        raise ManifestError("Manifest envelope must be an object.")
    _exact_keys(envelope, {"schema", "algorithm", "keyID", "payload", "signature"}, "Manifest envelope")
    if envelope["schema"] != ENVELOPE_SCHEMA or envelope["algorithm"] != ALGORITHM:
        raise ManifestError("Manifest envelope schema or signature algorithm is unsupported.")
    expected_key_id = public_key_id(public_key)
    if not isinstance(envelope["keyID"], str) or KEY_ID.fullmatch(envelope["keyID"]) is None:
        raise ManifestError("Manifest key ID is malformed.")
    if envelope["keyID"] != expected_key_id:
        raise ManifestError("Manifest key ID does not match the trusted public key.")
    payload_bytes = _decode_base64(envelope["payload"], "payload", MAX_PAYLOAD_BYTES)
    signature = _decode_base64(envelope["signature"], "signature", 384)
    if len(signature) != 384:
        raise ManifestError("Manifest signature must be one RSA-3072 signature.")
    try:
        payload = json.loads(payload_bytes)
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise ManifestError("Signed payload is not valid UTF-8 JSON.") from error
    validate_payload(payload)
    if canonical_payload(payload) != payload_bytes:
        raise ManifestError("Signed payload is not in canonical JSON form.")
    if verify_signature:
        with tempfile.NamedTemporaryFile() as signature_file, tempfile.NamedTemporaryFile() as payload_file:
            signature_file.write(signature)
            signature_file.flush()
            payload_file.write(payload_bytes)
            payload_file.flush()
            _run([
                "openssl", "dgst", "-sha256", "-verify", str(public_key),
                "-signature", signature_file.name,
                "-sigopt", "rsa_padding_mode:pss", "-sigopt", "rsa_pss_saltlen:digest",
                payload_file.name,
            ])
    return payload


def create_manifest(
    *, image: Path, private_key: Path, public_key: Path, output: Path,
    version: str, sequence: int, minimum_updater_version: str,
    release_notes: list[str], published_at: str,
) -> dict[str, Any]:
    if not image.is_file() or not 1 <= image.stat().st_size <= MAX_IMAGE_BYTES:
        raise ManifestError("Firmware image is missing, empty, or larger than an OTA slot.")
    derived = output.parent / f".{output.name}.derived-public.pem"
    try:
        derive_public_key(private_key, derived)
        if _public_der(derived) != _public_der(public_key):
            raise ManifestError("Firmware private key does not match the configured public key.")
    finally:
        if derived.exists():
            derived.unlink()
    payload = validate_payload({
        "schema": PAYLOAD_SCHEMA,
        "target": BOARD_TARGET,
        "channel": "stable",
        "version": version,
        "sequence": sequence,
        "publishedAt": published_at,
        "minimumUpdaterVersion": minimum_updater_version,
        "artifact": {
            "url": f"{RELEASE_URL_PREFIX}ILOBoardFirmware-{version}.bin",
            "size": image.stat().st_size,
            "sha256": hashlib.sha256(image.read_bytes()).hexdigest(),
        },
        "releaseNotes": release_notes,
    })
    payload_bytes = canonical_payload(payload)
    signature = _run([
        "openssl", "dgst", "-sha256", "-sign", str(private_key),
        "-sigopt", "rsa_padding_mode:pss", "-sigopt", "rsa_pss_saltlen:digest",
    ], input_data=payload_bytes)
    if len(signature) != 384:
        raise ManifestError("Manifest signer did not produce one RSA-3072 signature.")
    envelope = {
        "schema": ENVELOPE_SCHEMA,
        "algorithm": ALGORITHM,
        "keyID": public_key_id(public_key),
        "payload": base64.b64encode(payload_bytes).decode("ascii"),
        "signature": base64.b64encode(signature).decode("ascii"),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(envelope, sort_keys=True, indent=2) + "\n")
    load_and_validate_envelope(output, public_key)
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    create = subparsers.add_parser("create", help="create and self-verify a signed manifest")
    create.add_argument("--image", required=True, type=Path)
    create.add_argument("--private-key", required=True, type=Path)
    create.add_argument("--public-key", required=True, type=Path)
    create.add_argument("--output", required=True, type=Path)
    create.add_argument("--version", required=True)
    create.add_argument("--sequence", required=True, type=int)
    create.add_argument("--minimum-updater-version", required=True)
    create.add_argument("--published-at", required=True)
    create.add_argument("--release-note", action="append", required=True)
    verify = subparsers.add_parser("verify", help="verify a manifest without changing it")
    verify.add_argument("--manifest", required=True, type=Path)
    verify.add_argument("--public-key", required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.command == "create":
            payload = create_manifest(
                image=args.image, private_key=args.private_key, public_key=args.public_key,
                output=args.output, version=args.version, sequence=args.sequence,
                minimum_updater_version=args.minimum_updater_version,
                release_notes=args.release_note, published_at=args.published_at,
            )
            print(f"Signed firmware manifest created for {payload['version']} (sequence {payload['sequence']}).")
        else:
            payload = load_and_validate_envelope(args.manifest, args.public_key)
            print(f"Signed firmware manifest verified for {payload['version']} (sequence {payload['sequence']}).")
    except ManifestError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
