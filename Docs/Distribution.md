# Mac distribution

Lore is distributed directly from GitHub Releases as a ZIP containing the signed, notarized app, the MIT license and installation instructions. It is not an App Store submission.

## Requirements

- Apple Silicon Mac and Xcode.
- An Apple Developer Program team with a valid Developer ID Application signing identity in the local keychain.
- Access to Apple's notarization service through Xcode or a separately configured notarytool keychain profile.

Keep private keys and authentication credentials in the keychain. Never add them, archive logs or local signing overrides to Git.

## Create the archive

Find your public identity fingerprint with `security find-identity -v -p codesigning`, then run:

```sh
Scripts/archive-release.sh DEVELOPER_ID_IDENTITY_SHA1 TEAM_ID
```

The script creates a fresh directory under `build/distribution/`, builds an archive with hardened runtime and secure timestamps, and checks both the app and embedded helper. The app is the archive's only installable product; the helper remains embedded inside it.

## Notarize with Xcode

1. Open the generated `Lore.xcarchive` in Xcode.
2. In Organizer, choose **Distribute App → Direct Distribution**.
3. Submit the app, then wait for **Ready to distribute**.
4. Choose **Export Notarized App**, saving the exported bundle as `Lore.app`.

The first release used the existing Xcode account, without creating or exporting an API key or app-specific password. Xcode's exported app includes its notarization ticket.

## Package and verify

```sh
Scripts/package-release.sh /path/to/Lore.app /path/to/Lore-0.1.0-arm64.zip
```

The script verifies the signature, stapled ticket, Gatekeeper assessment, architecture and absence of debugging entitlement. It includes the MIT license and install instructions alongside the app. It never packages the build directory, signing overrides, activity database or logs.

Before publishing, extract the final ZIP into a fresh folder and repeat:

```sh
codesign --verify --deep --strict /path/to/extracted/Lore.app
xcrun stapler validate /path/to/extracted/Lore.app
spctl --assess --type execute --verbose=2 /path/to/extracted/Lore.app
```

Create a SHA-256 checksum using the ZIP's basename, attach the ZIP and checksum file to the release, and ensure its tag points to the corresponding source revision. Notarization is Apple's automated security and signing check, not an App Store editorial review.

## Installing and updating

Extract the ZIP, drag Lore.app into Applications, then open it. Git access is granted through Lore's folder picker. Pulse's lid-closed mode has a separate macOS approval on the Pulse page.

For updates that change the embedded helper: stop Pulse, remove its system-access registration, replace the app, then enable system access again. The local development installer protects against replacing a different running helper. Do not silently replace the helper during an active Pulse session.

## First distribution validation

The 0.1.0 candidate was accepted by Apple's notary service on 14 September 2026. Gatekeeper reported `accepted` and `source=Notarized Developer ID` for the exported app and the copy extracted from the final ZIP. Both app and helper passed the team's signing requirements without the `get-task-allow` entitlement. No user development data or signing private key is included in the release package.
