# macOS distribution

The ILO Board companion is a SwiftPM menu-bar application without an Xcode project. The repository assembles a conventional `.app`, creates a DMG, applies Developer ID signatures with the hardened runtime, submits the DMG to Apple notarization, staples the result, and only then permits a Google Cloud Storage upload.

## Local developer artifact

No Apple account or release credentials are needed for a local build:

```bash
make app
make package-dmg
```

This produces:

- `artifacts/ILO Board.app`
- `artifacts/ILOBoard-0.1.0.dmg`

The app is universal (`arm64` + `x86_64`) and ad-hoc signed with the hardened-runtime option. It is suitable for local inspection but not public distribution.

## Release prerequisites

- Active Apple Developer Program membership.
- A `Developer ID Application` certificate in the login Keychain.
- Xcode Command Line Tools with `codesign`, `xcrun notarytool`, and `xcrun stapler`.
- A notarytool Keychain profile.
- Google Cloud CLI authenticated to an account that can create objects in the target bucket.
- Public-read configuration on the chosen bucket/object path if the GitHub README should offer a direct anonymous download.

Copy the example configuration:

```bash
cp Config/release.env.example Config/release.env
```

Set the exact signing identity shown by:

```bash
security find-identity -v -p codesigning
```

Create a notary profile once. One supported Apple-ID form is:

```bash
xcrun notarytool store-credentials ilo-board-notary \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

The password is stored by `notarytool` in Keychain and must not be written into `Config/release.env`. App Store Connect API-key authentication is also supported by Apple if preferred.

Verify Google Cloud authentication without uploading:

```bash
gcloud auth list
gcloud storage ls gs://ilo-public/ilo-board/
```

The default destinations are:

- Stable: `gs://ilo-public/ilo-board/ILOBoard-latest.dmg`
- Versioned: `gs://ilo-public/ilo-board/releases/ILOBoard-VERSION.dmg`
- Public stable URL: `https://storage.googleapis.com/ilo-public/ilo-board/ILOBoard-latest.dmg`

Override the `ILO_BOARD_PUBLIC_*` variables in the ignored `Config/release.env` when a different bucket is desired.

## Build and publish

Run the complete local release pipeline:

```bash
make release-local
```

It performs these gates in order:

1. Builds both CPU architectures and creates the `.app` bundle.
2. Applies the Developer ID signature and hardened runtime.
3. Creates and signs the DMG.
4. Waits for Apple notarization.
5. Staples and validates the notarization ticket.
6. Creates `ILOBoard-latest.dmg` only from that verified DMG.

Inspect the result before any external write:

```bash
codesign --verify --deep --strict "artifacts/ILO Board.app"
spctl --assess --type execute --verbose "artifacts/ILO Board.app"
xcrun stapler validate artifacts/ILOBoard-0.1.0.dmg
```

Publish only after those checks pass:

```bash
make release-distribute
```

The distribution command revalidates the stapled ticket and confirms that the stable alias is byte-identical to the versioned DMG before invoking `gcloud storage cp`. It never changes bucket IAM or public-access policy.

Finally verify the anonymous public URL before changing the README from “not published” to a download button:

```bash
curl -I https://storage.googleapis.com/ilo-public/ilo-board/ILOBoard-latest.dmg
```

A successful public release should return `HTTP 200`, not `403` or `404`.

## Versioning

Edit `Config/version.env` for each release:

- `ILO_BOARD_MARKETING_VERSION` is the user-visible semantic version.
- `ILO_BOARD_BUILD_NUMBER` must increase for every notarized build.

Commit the version change and release notes before producing the public artifact. Automatic app updates are not implemented yet; the stable GCS object is a direct download only.
