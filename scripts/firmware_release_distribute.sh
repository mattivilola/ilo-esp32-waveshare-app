#!/bin/zsh
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

load_release_config
require_firmware_signing_material
ensure_command gcloud

release_image="$(firmware_release_image)"
release_manifest="$(firmware_release_manifest)"
release_sdkconfig="$(firmware_release_sdkconfig)"
version="$(firmware_version)"
versioned_uri="$ILO_BOARD_FIRMWARE_RELEASES_URI/ILOBoardFirmware-$version.bin"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT

[[ -f "$release_image" && -f "$release_manifest" && -f "$release_sdkconfig" ]] \
  || fail "Run make firmware-release-local first; signed release artifacts are incomplete."
"$ILO_BOARD_ROOT/tools/board" ota-verify \
  --image "$release_image" \
  --public-key "$ILO_BOARD_FIRMWARE_PUBLIC_KEY" \
  --sdkconfig "$release_sdkconfig"
python3 "$ILO_BOARD_ROOT/tools/firmware_manifest.py" verify \
  --manifest "$release_manifest" \
  --public-key "$ILO_BOARD_FIRMWARE_PUBLIC_KEY"

local_payload="$temporary_dir/local-payload.json"
python3 - "$release_manifest" "$release_image" "$versioned_uri" > "$local_payload" <<'PY'
import base64, hashlib, json, pathlib, sys
manifest_path = pathlib.Path(sys.argv[1])
image_path = pathlib.Path(sys.argv[2])
expected_uri = sys.argv[3]
envelope = json.loads(manifest_path.read_text())
payload = json.loads(base64.b64decode(envelope["payload"], validate=True))
image = image_path.read_bytes()
if payload["artifact"]["size"] != len(image) or payload["artifact"]["sha256"] != hashlib.sha256(image).hexdigest():
    raise SystemExit("Signed manifest does not describe the local signed image.")
expected_url = "https://storage.googleapis.com/" + expected_uri.removeprefix("gs://")
if payload["artifact"]["url"] != expected_url:
    raise SystemExit("Signed manifest URL does not match the configured GCS release destination.")
print(json.dumps(payload, sort_keys=True))
PY

if gcloud storage ls "$ILO_BOARD_FIRMWARE_MANIFEST_URI" >/dev/null 2>&1; then
  prior_manifest="$temporary_dir/prior-manifest.json"
  gcloud storage cp "$ILO_BOARD_FIRMWARE_MANIFEST_URI" "$prior_manifest"
  python3 "$ILO_BOARD_ROOT/tools/firmware_manifest.py" verify \
    --manifest "$prior_manifest" \
    --public-key "$ILO_BOARD_FIRMWARE_PUBLIC_KEY"
  python3 - "$prior_manifest" "$release_manifest" <<'PY'
import base64, json, pathlib, sys
def sequence(path):
    envelope = json.loads(pathlib.Path(path).read_text())
    return json.loads(base64.b64decode(envelope["payload"], validate=True))["sequence"]
prior, candidate = map(sequence, sys.argv[1:])
if candidate <= prior:
    raise SystemExit(f"Firmware manifest sequence must increase: published={prior}, candidate={candidate}")
PY
fi

immutable_cache_control="public,max-age=31536000,immutable"
mutable_cache_control="no-cache,max-age=0,must-revalidate"
gcloud storage cp --if-generation-match=0 --cache-control="$immutable_cache_control" "$release_image" "$versioned_uri"
remote_image="$temporary_dir/remote-image.bin"
gcloud storage cp "$versioned_uri" "$remote_image"
cmp -s "$release_image" "$remote_image" || fail "Remote firmware bytes differ; manifest publication is blocked."
gcloud storage cp --cache-control="$mutable_cache_control" "$release_manifest" "$ILO_BOARD_FIRMWARE_MANIFEST_URI"
remote_manifest="$temporary_dir/remote-manifest.json"
gcloud storage cp "$ILO_BOARD_FIRMWARE_MANIFEST_URI" "$remote_manifest"
cmp -s "$release_manifest" "$remote_manifest" || fail "Remote firmware manifest differs from the signed local manifest."
python3 "$ILO_BOARD_ROOT/tools/firmware_manifest.py" verify \
  --manifest "$remote_manifest" \
  --public-key "$ILO_BOARD_FIRMWARE_PUBLIC_KEY"
log "Published immutable $versioned_uri, verified it byte-for-byte, then published the signed manifest."
