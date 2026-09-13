# Open-source readiness review

Review date: 14 September 2026. Current direction: the complete app is free, with optional donations. After this review, the maintainer approved the MIT license and making the full repository public on 14 September 2026. The [license](../LICENSE) covers the code, documentation and original project artwork.

## Recommended public scope

| Component | Recommendation | Reason |
| --- | --- | --- |
| SwiftUI app, calendar, timeline, projects and preferences | Publish | This is the usable product, not a restricted demonstration. |
| Codex, Claude Code, Gemini CLI and Git integrations | Publish | Enables auditing, compatibility fixes and community contributions. |
| Storage, cache, parsers and activity grouping | Publish | Makes local-first behavior and the data boundary inspectable. |
| Pulse UI, policies, XPC protocol and helper implementation | Publish | Code that manages system power should be reviewable. Signing keys are not part of the implementation. |
| Tests, synthetic fixtures and build scripts | Publish | Contributors need a reproducible project and useful regression checks. |
| Project-created vector shapes, icon renderer and app icon assets | Include in the proposed scope | The tracked assets have reproducible project renderers; confirm the intended license coverage and brand policy before release. |
| Documentation | Publish the user and contributor documentation | Keep the README product-focused and the technical details in separate pages. |

There is no private Pro implementation to preserve. No third-party package dependency is declared in `Package.swift`; Apple frameworks remain platform dependencies. Provider icons are obtained from installed applications at runtime, not distributed as a copied logo pack in the repository. This inventory does not establish ownership of any undisclosed third-party contributions.

## Keep local

- Signing overrides and private keys, certificates or provisioning material.
- Agent conversations, credentials and authentication/configuration directories.
- Lore's database, bookmark grants, parsed cache and power-test reports.
- Build output, database backups, personal screenshots and crash logs.

The checked-in signing configuration contains portable variables and an optional ignored local override. The public helper authenticates both peers; it does not require publishing any credential. A contributor can build the app ad hoc; enabling the privileged service requires their own suitable signing setup and macOS approval.

## Checks performed

- Reviewed the 112 tracked files at the start of this task and the three-commit Git history.
- Scanned 119 historical blob objects for recognizable credential formats, private-key headers, personal home paths and accidentally committed local signing/database files: no matches detected. This is a bounded pattern scan, not a guarantee that every possible secret format is absent.
- No tracked symlinks or bundled third-party package directory was found.
- Created a tracked-only checkout without `Config/Signing.local.json` or `Config/Signing.local.xcconfig`.
- Built the native Release app from that checkout successfully. Its resulting signature was ad hoc, with no team identifier.
- Added test-host isolation: an in-memory app database and no launch-time live indexing under XCTest. The app-host log confirmed this path.
- Ran Xcode tests from the isolated checkout: 78 tests passed.
- At the start of the review, the repository was private and no packaged GitHub release existed.
- Confirmed that the donation profile is not public yet; the README links to a support page instead of advertising a live payment destination.

## Publication decision

The maintainer selected MIT and authorized publishing the complete repository on 14 September 2026. The license has been added and linked from the README and contributing guide. No private Pro module or feature paywall is planned.

The subsequent 0.1.0 distribution was signed with Developer ID and accepted by Apple notarization. Its packaged app passed Gatekeeper after extraction; see [Distribution.md](Distribution.md) for the release process. GitHub Sponsors approval and donation-link activation are also separate from the source publication.
