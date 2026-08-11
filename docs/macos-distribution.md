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
- `artifacts/ILOBoard-0.1.1.dmg`

The app is universal (`arm64` + `x86_64`) and ad-hoc signed with the hardened-runtime option. It is suitable for local inspection but not public distribution.

## Release prerequisites

- Active Apple Developer Program membership.
- A `Developer ID Application` certificate in the login Keychain.
- Xcode Command Line Tools with `codesign`, `xcrun notarytool`, and `xcrun stapler`.
- A notarytool Keychain profile.
- Google Cloud CLI authenticated to an account that can create objects in the target bucket.
- Public-read configuration on the chosen bucket/object path if the GitHub README should offer a direct anonymous download.
- A Sparkle EdDSA private key stored in the login Keychain; only its public key belongs in local release configuration and the app bundle.

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

Resolve the pinned Sparkle dependency and create or read the organization update-signing key once:

```bash
make sparkle-generate-keys
```

Copy only the printed base64 public key into `ILO_BOARD_SPARKLE_PUBLIC_ED_KEY` in the ignored `Config/release.env`. Sparkle keeps the private key in Keychain. Back it up through a secure credential process; never commit it, export it into this repository, or upload it to GCS.

Verify Google Cloud authentication without uploading:

```bash
gcloud auth list
gcloud storage ls gs://ilo-public/ilo-board/
```

The default destinations are:

- Stable: `gs://ilo-public/ilo-board/ILOBoard-latest.dmg`
- Versioned: `gs://ilo-public/ilo-board/releases/ILOBoard-VERSION.dmg`
- Public stable URL: `https://storage.googleapis.com/ilo-public/ilo-board/ILOBoard-latest.dmg`
- Sparkle appcast: `gs://ilo-public/ilo-board/appcast.xml`
- Public appcast URL: `https://storage.googleapis.com/ilo-public/ilo-board/appcast.xml`

Override the `ILO_BOARD_PUBLIC_*` variables in the ignored `Config/release.env` when a different bucket is desired.

## Build and publish

Run the complete local release pipeline:

```bash
make release-local
```

This command performs no Google Cloud writes.

It performs these gates in order:

1. Builds both CPU architectures and creates the `.app` bundle.
2. Applies the Developer ID signature and hardened runtime.
3. Creates and signs the DMG.
4. Waits for Apple notarization.
5. Staples and validates the notarization ticket.
6. Verifies the embedded Sparkle feed URL/public key and nested updater signatures.
7. Creates `ILOBoard-latest.dmg` only from that verified DMG.

Inspect the result before any external write:

```bash
codesign --verify --deep --strict "artifacts/ILO Board.app"
spctl --assess --type execute --verbose "artifacts/ILO Board.app"
xcrun stapler validate artifacts/ILOBoard-0.1.1.dmg
```

Publish only after those checks pass:

```bash
make release-distribute
```

The distribution command revalidates the stapled ticket, confirms that the stable alias is byte-identical to the versioned DMG, signs the archive with the Keychain-backed Sparkle EdDSA key, validates the generated XML, and embeds bounded history from the newest `CHANGELOG.md` entry. It uploads the immutable versioned DMG with a one-year immutable cache policy, then the stable alias and finally `appcast.xml` with mandatory revalidation. This prevents mutable public URLs from serving a replaced older release through shared cache. It never changes bucket IAM or public-access policy.

Finally verify both anonymous public URLs before announcing the release:

```bash
curl -I https://storage.googleapis.com/ilo-public/ilo-board/ILOBoard-latest.dmg
curl -I https://storage.googleapis.com/ilo-public/ilo-board/appcast.xml
```

A successful public release should return `HTTP 200`, not `403` or `404`.

## Versioning

Inspect or prepare release metadata with:

```bash
make release-version
make version-patch   # or version-minor / version-major
```

The version command requires a clean worktree, increments both semantic and build versions, and prepares the next `CHANGELOG.md` entry from commits since the latest release tag. It does not commit, tag, push, notarize, or upload. Review its changes, then use the explicit steps:

```bash
make release-commit
make release-tag
make release-push
make release-local
make release-distribute
```

`Config/version.env` contains:

- `ILO_BOARD_MARKETING_VERSION` is the user-visible semantic version.
- `ILO_BOARD_BUILD_NUMBER` must increase for every notarized build.

Sparkle 2.9.2 is pinned through SwiftPM. Signed builds expose **Check for Updates…**, and Sparkle manages the user's automatic-check preference. Updates are accepted only when the appcast points to a Developer-ID-signed/notarized DMG with a valid EdDSA enclosure signature and a higher `CFBundleVersion`.

Before announcing a release, test one genuine installed-version transition (for example `0.1.1 (2)` to `0.1.2 (3)`) from `/Applications`. Ad-hoc builds and copies running from the DMG are useful for UI work but do not prove the production updater installation path.
