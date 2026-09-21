# Architecture and local development


- `App/`: app lifecycle, navigation, observable refresh state, menu bar.
- `Features/`: Today (including usage), Timeline, Projects, activity/session details, Settings.
- `Core/Access/`: lexical repository allowlist and persistent folder grants.
- `Core/Power/`: shared, testable power lease logic and narrowly scoped XPC protocol.
- `Helper/`: separately signed privileged power service, embedded but never registered automatically.
- `Core/Models/`: four SwiftData entities plus small, Sendable metadata values.
- `Core/Database/`: local container configuration with CloudKit explicitly disabled.
- `Core/Parsers/`: bounded streaming JSONL reader.
- `Core/Collectors/`: provider discovery/parsing protocol.
- `Core/Services/`: indexing actor and pure deterministic grouping.
- `Integrations/Codex/`: discovery and allowlisted metadata decoder.
- `Integrations/Git/`: private read-only command runner and NUL-delimited output parser.
- `DesignSystem/`: shared native rows and formatting.

The indexing actor owns discovery → parsing → root resolution → Git enrichment → one SwiftData save → persisted activity. It creates its own model context off the main actor. Provider failures are isolated, and per-provider diagnostics explain missing or unreadable data. Only a Sendable report crosses into observable UI state; views query persisted models. A failed save rolls back instead of publishing a partial refresh. One unreadable or malformed file does not discard other sessions.

Stable identifiers use SHA-256 with length-framed inputs: canonical path for projects, provider + Codex session ID for sessions, project ID + commit hash for commits, and project ID + interval start for blocks. Database uniqueness and explicit upserts prevent duplicates. When grouping changes, superseded blocks are removed in the same save. Sessions and periods survive missing source files. Timestamp-only session intervals are stored to make regrouping possible without retaining conversations. The stored commit hash is named `commitHash` because `hash` is reserved in Core Data; the domain exposes `hash` as a computed accessor.


## Privacy and storage

**Your development data stays on this Mac.**

- Lore's database is `~/Library/Application Support/Lore/Lore.store` (plus SQLite support files).
- Codex discovery reads only regular JSONL files in `~/.codex/sessions` and `~/.codex/archived_sessions`. Lore never opens Codex authentication, configuration, or private SQLite databases.
- The decoder skips prompts, responses, instructions, tool inputs/outputs, reasoning, and source code. They are neither persisted nor logged. The line reader limits individual records to 8 MiB and recovers at the next newline.
- Stored data includes paths, dates, provider/model, optional token counters, project relationships, Git author and commit messages/statistics, and timestamp intervals. Commit messages can themselves contain personal information and remain local.
- Git remote credentials, URL queries, and fragments are stripped before persistence.
- Git commands use `/usr/bin/git` directly, never a shell. No optional locks, fsmonitor hooks, external diffs, text conversion, network commands, or repository writes. Git subprocesses have a 30-second termination watchdog.
- No analytics, telemetry, accounts, sync, or LLM calls. The only network request is an explicit update check against Lore's public GitHub release endpoint; it never includes activity data. No simulated activity appears in the live app.

The app is not sandboxed. **Settings → Sources & Access** provides explicit development-folder selection and read-only security-scoped bookmarks. Git enrichment is blocked before filesystem canonicalization or subprocess execution unless a project lies inside a chosen root; existing indexed history remains visible. Agent source folders can be selected separately and each provider can be paused. Bookmarks resolve without displaying UI and stale grants show a renewal action.

macOS permission identity is kept stable by signing updates with the same identity/team and using the installed copy. An old ad-hoc build may require a final grant when moving to the signed version. This is not a blanket filesystem permission and does not bypass macOS TCC; bookmarks do not prevent a user or macOS from revoking access.

Lore can register its main application as a Login Item through `SMAppService.mainApp`. Registration is controlled by the user from Appearance, and macOS reports when approval is still required. The primary window has a suppressed default launch behavior, so automatic startup brings back the menu bar and notch without opening a history window.

Official builds are Developer ID signed, notarized and distributed through GitHub Releases. The in-app update check is manual: it reads only the public latest-release document, validates the repository release URL, and opens the release page when a newer semantic version exists. Lore does not download or replace itself in the background, which also keeps Pulse helper updates explicit.


## Diagnostics and validation

- `swift run LoreDiagnostics --audit-sessions` reports aggregate provider metadata and valid chat-link counts without printing conversations or invoking Git.
- `swift run LoreDiagnostics --validate-store PATH` checks a disposable copy of a database and its relationships. Do not use a contributor's real database as a fixture.
- The default `swift run LoreDiagnostics` reads real local sources and Git repositories, indexes twice into its own temporary store, and prints aggregate counts. It is an optional local audit, not a prerequisite for contributing.
- Pulse's service architecture and completed hardware checks are documented in [ClosedLid-AppleSilicon.md](ClosedLid-AppleSilicon.md).

The main app, helper, tests and build scripts are intended to remain in the same public repository. Runtime data and signing credentials stay local.
