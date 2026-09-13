# Contributing to Lore

Thanks for helping make Lore a useful, native Mac app. Small fixes, clear bug reports, accessibility improvements, design feedback and documentation are welcome.

The repository is being prepared for its first public source release. The maintainer still needs to select and apply the open-source license; this guide does not grant a license by itself.

## Build Lore

You need an Apple Silicon Mac, macOS 15 or newer, and Xcode with Swift 6 support. The current development toolchain is Xcode 26.6 / Swift 6.3.3; older Xcode releases have not yet been independently validated.

```sh
git clone https://github.com/wassimkanze/Lore.git
cd Lore
xcodebuild -project Lore.xcodeproj -scheme Lore -configuration Debug -derivedDataPath build build
```

Or open `Lore.xcodeproj` and run the Lore scheme on My Mac. There are no third-party package dependencies.

The default build uses ad-hoc signing. You can explore the app and its metadata features without the maintainer's signing identity. Pulse's privileged lid-closed service requires an appropriately signed Release build and macOS approval; ad-hoc builds cannot enable that service.

## Optional local signing

Create an ignored `Config/Signing.local.json` using an identity already available in your own keychain:

```json
{"identity":"YOUR_CODE_SIGNING_IDENTITY_SHA1","team":"YOUR_TEAM_ID"}
```

Then run `python3 Scripts/generate_project.py`. It writes an ignored local xcconfig override. The shared project contains portable variables, never the maintainer's private key or signing settings.

For an installed local build:

```sh
xcodebuild -project Lore.xcodeproj -scheme Lore -configuration Release -derivedDataPath build build
# Quit Lore first. This ends any Pulse session owned by that app instance.
Scripts/install-local.sh Release
```

The installer preserves an unchanged running helper. If the helper itself changes, stop Pulse and remove its system-access registration before installing; enable it again afterwards. The script refuses to replace a different helper while its service is running.

## Tests

```sh
swift test
xcodebuild -project Lore.xcodeproj -scheme Lore -configuration Debug -derivedDataPath build test
```

Core tests use synthetic fixtures and disposable repositories. Keep tests deterministic and avoid changing real system sleep settings. App-hosted tests should use an in-memory app database and leave live monitoring disabled.

After adding Swift source files, regenerate the project:

```sh
python3 Scripts/generate_project.py
```

## Bug reports and pull requests

Describe the expected behavior, the actual behavior and how to reproduce the problem. Include your macOS and Lore version when relevant. Explain the user-visible result of a change and the checks you ran.

Do not attach real Codex, Claude or Gemini logs, prompts, responses, credentials, private source code, security-scoped bookmarks or the Lore database. Create a small synthetic fixture containing only the metadata needed to reproduce a parser problem. Sanitize screenshots before sharing them.

`LoreDiagnostics` is a developer utility that can read real local history. It is optional, not required to run the tests. Its diagnostic commands and format assumptions are documented in [the architecture](Docs/Architecture.md) and [integration notes](Docs/Integrations.md).

## Project principles

- Native macOS UI and local-first operation.
- Read-only access to external development data.
- No telemetry, conversation uploads or feature paywalls.
- No productivity scoring or invented activity data.
- Keep the code straightforward and the UI calm.
