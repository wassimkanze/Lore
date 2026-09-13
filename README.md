# Lore

**Remember what you built.** A native, local-first macOS memory layer for AI-assisted development.

This is the 0.1 foundation: Codex and Claude Code discovery, a Gemini CLI reader, read-only Git enrichment, a persisted activity timeline, and a menu bar utility. Requires an Apple Silicon Mac (arm64), macOS 15+ and Xcode 16+ (validated here with Xcode 26.6 / Swift 6.3.3). No dependencies or network services.

## Run

Open `Lore.xcodeproj`, select the **Lore** scheme and **My Mac**, then Run for development. For everyday use, build Release and install at the stable `~/Applications/Lore.app` path. This Mac uses an existing Apple Development identity; the identity hash and team are stored only in ignored `Config/Signing.local.json` and its generated `Config/Signing.local.xcconfig`. The shared Xcode project uses portable signing variables.

On another development Mac, create that file with `{"identity":"YOUR_CODE_SIGNING_IDENTITY_SHA1","team":"YOUR_TEAM_ID"}` using an identity already present in your keychain, then run `python3 Scripts/generate_project.py`. No private key is stored in the project. Without local signing configuration the app builds ad hoc, but privileged power setup is unavailable. Distribution signing/notarization remains a later milestone.

```sh
python3 Scripts/generate_project.py
xcodebuild -project Lore.xcodeproj -scheme Lore -configuration Release -derivedDataPath build build
# Quit the running copy before replacing it.
Scripts/install-local.sh Release
open "$HOME/Applications/Lore.app"
```

Today is the default destination. Indexing runs at launch; use the toolbar refresh button, **⌘R**, Settings, or the menu bar to refresh manually. The first scan can take a few seconds for large histories. The app remains usable while it scans.

## Verify

```sh
swift test
xcodebuild -project Lore.xcodeproj -scheme Lore -configuration Debug -derivedDataPath build test
swift run LoreDiagnostics
```

`LoreDiagnostics` reads real local session metadata and repositories, indexes twice into a disposable store, and reopens it. It prints aggregate counts only. The test suite uses synthetic fixtures and disposable Git repositories. Test setup never mutates an existing repository.

The native app is built with Xcode. The Swift package exposes the same core code for fast tests and diagnostics; it is not an alternate frontend. After adding source files, run `python3 Scripts/generate_project.py` to regenerate the checked-in Xcode project and shared scheme without additional tools.

## Architecture

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
- No analytics, telemetry, accounts, sync, external APIs, or LLM calls. No simulated activity in the live app.

The app is not sandboxed. **Settings → AI sources / Development folders** provides explicit development-folder selection and read-only security-scoped bookmarks. Git enrichment is blocked before filesystem canonicalization or subprocess execution unless a project lies inside a chosen root; existing indexed history remains visible. Agent source folders can be selected separately and each provider can be paused. Bookmarks resolve without displaying UI and stale grants show a renewal action.

macOS permission identity is kept stable by signing updates with the same identity/team and using the installed copy. An old ad-hoc build may require a final grant when moving to the signed version. This is not a blanket filesystem permission and does not bypass macOS TCC; bookmarks do not prevent a user or macOS from revoking access. Notarization and distribution packaging remain future work.

## Observed Codex format and assumptions

Inspected the local JSONL structure on 2026-09-09, including files produced by Codex Desktop CLI version 0.153.1. This is a defensive integration with an evolving local format, not a guaranteed public schema.

| Record | Metadata used |
| --- | --- |
| `session_meta` | `payload.id` (fallback `session_id`), timestamp, first absolute `cwd` |
| `turn_context` | model and fallback cwd; outer timestamp is an activity observation |
| `event_msg` | outer timestamps for `task_started`, `task_complete`, `item_completed`, `token_count` |
| `event_msg / token_count` | `info.total_token_usage` input/output/cached input counters |
| `token_usage_record` | `thread_token_usage` cumulative counters and outer timestamp |

The real validation found metadata for **120 sessions** across active and archived directories: all 120 had a model and token totals. They resolved to **15 projects**, **53 Git commits**, and **68 activity blocks** at that snapshot. Those numbers will evolve as you work.

- `endedAt` means **last observed activity**, not proof that the agent session has permanently ended. It is nil if there is no activity timestamp.
- A session can be reopened days later. Activity observations are split at gaps exceeding the configurable `ActivityPolicy.inactivityThreshold` (30 minutes), then merged with nearby sessions in the same project. Point observations contribute zero time; no duration is invented.
- Observed activity is an estimate, not keyboard or CPU tracking. Explicit Codex task boundaries exclude gaps between tasks, even when those tasks share an activity block. Older formats still use timestamp/inactivity estimates. Overlap across projects is counted once. Today clips time at local-day boundaries; Timeline displays cross-midnight periods on both dates.
- Cumulative token counters use the greatest valid observed value, avoiding double-counting the two record formats and repeated snapshots. Missing or invalid counters stay nil. They are session-wide high-water marks; resets, forks, compaction, or future format changes can make them approximate. Latest observed model is shown if a session changes models.
- A session belongs to its first valid working directory, resolved to a canonical Git root when available. Other directories mentioned inside a conversation are ignored. Non-Git or missing directories fall back to path-based projects. Unresolvable sessions remain indexed without inventing a project.
- Git history is taken from local `HEAD`, bounded by that project's observed session dates plus the inactivity threshold on each end. No fetching or all-branch scan. Detached HEAD, unborn repositories and missing remotes are supported.
- Commits are associated with the nearest period in the same project within 30 minutes, at most once. Proximity does not imply AI authorship. Commit statistics are summed per commit, so “file changes” is not a distinct-path count. Binary files count as changes without invented line totals; merge commits may have zero numstat totals.
- The versioned local cache at `~/Library/Caches/Lore/session-index-v2.json` stores only parsed activity metadata. File identity, nanosecond modification/change times and dependency fingerprints invalidate changed, replaced or truncated files. Unchanged files (including unparseable ones) are reused across launches; corrupt or incompatible caches fall back to parsing. Source discovery still enumerates filenames; changed files are parsed fully. Byte-offset checkpoints and filesystem watching remain future refinements.

## Next milestones

1. Add persistent file signatures/offsets and efficient filesystem observation, with rotation/truncation tests.
2. Improve period estimates using explicit task boundaries and richer handling of project changes, archived/forked sessions, and Git-only activity.
3. Physically validate closed-lid operation and recovery, then add distribution signing/notarization and broader macOS 15 UI coverage.

Local AI summaries, further providers, semantic search, licensing and monetization remain out of scope.

## Overview and visual identity

Today brings development metrics, the clickable 26-week activity calendar, daily activity and AI usage together on one page. The calendar keeps the original compact square heatmap cells and even spacing; selecting a date updates the day's metrics and activity while session-wide token totals remain clearly labeled “All history.” There is no separate usage destination or bar chart. Cached input is included in input, and models are ranked by session count using the latest observed model.

Timeline has local project/model/commit search and provider/project filters. Projects has a searchable master/detail view with activity, sessions and commits on a single scrolling page, with inline expansion for long lists. Preferences are grouped into Appearance, Sources & Access and Privacy. Diagnostics remain separate from daily controls. Refresh shows cancellable progress without resetting the selected date or filters. Native transitions respect Reduce Motion.

Lore's curved star is a shared vector shape used in the app, menu bar, and app icon. Rebuild the icon assets locally with:

```sh
swiftc -parse-as-library -swift-version 6 Lore/DesignSystem/LorePreferences.swift Lore/DesignSystem/LoreMark.swift Scripts/Brand/main.swift -o /tmp/lore-brand-renderer
/tmp/lore-brand-renderer Lore/Resources/Assets.xcassets/AppIcon.appiconset
```


## Claude Code and Gemini CLI integrations

Added on 2026-09-10. The indexer now accepts a collection of `AIProviderIntegration` implementations. Every provider uses namespaced stable session IDs, so equal source IDs from different agents cannot collide. A session without a resolvable project retains its own activity blocks labeled “Unassigned project”; it does not create a fictional project. Nearby sessions from different agents in a known project share the same activity grouping.

**Claude Code:** reads only the main `~/.claude/projects/<project>/*.jsonl` files. Two real sessions were found on this Mac, produced by versions 2.1.255 and 2.1.260. Allowed metadata is `sessionId`, `cwd`, timestamps, `message.id`, model and usage counters. Repeated assistant blocks with the same message ID are collapsed using the greatest observed counter values. Input includes uncached input, cache reads and cache creation; cached input reports reads only. This normalizes the cache convention to Lore's existing input-inclusive representation. Prompts, attachments, title records, tool results and response content are ignored. Nested subagent logs are deliberately excluded because they can reuse the parent's session ID; aggregate subagent accounting needs separate validation.

**Gemini CLI:** supports legacy `~/.gemini/tmp/<project>/chats/session-*.json` and current `.jsonl` files. The parser was implemented against the [official recording types](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingTypes.ts), [record loader](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingService.ts) and [project registry](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/config/projectRegistry.ts). It decodes session identity, timestamps, model and token metadata; repeated message IDs replace earlier snapshots. JSONL metadata updates, checkpoints and rewind records are supported. Counts reflect the remaining recorded history after a rewind, not deleted requests or an invoice. Gemini thought tokens are counted as output; cached tokens remain a subset of input. Optional tool-specific token counters are not folded into totals. Legacy JSON reads are bounded to 32 MiB; JSONL uses the existing streaming limit. Malformed messages are skipped where the surrounding JSON is valid, and an invalid file cannot block other sessions.

Project roots come from the adjacent `.project_root` marker or the explicit path-to-slug mapping in `~/.gemini/projects.json`. A recorded directory is used only if its SHA-256 matches `projectHash`; extra workspace directories are not assumed to be the project root. Changes to project-mapping files invalidate cached session metadata. Authentication, settings, account databases and arbitrary cached browser content are never read by these integrations.

On this Mac, **Gemini desktop was detected but no `.gemini` CLI directory was present**. The inspected desktop store schemas exposed settings/account state, not usable session history. Lore reports this distinction in Settings and does not manufacture Gemini activity, inspect credentials, query private Google endpoints or install the CLI. The Gemini reader is covered by synthetic fixtures but cannot yet be validated against real local Gemini CLI sessions on this Mac.

New tests cover Claude usage deduplication and cache normalization, Gemini JSON/JSONL updates and rewinds, malformed data, cross-provider identity, discovery failure isolation, missing projects, project-map cache invalidation, duplicate-free reindexing and preservation of source fixture bytes.


## Grouped live island and keep awake

One animated Lore star to the right of the notch now represents all AI providers. It stays dim and still at rest; a wave travels through its branches while tasks work, becoming more pronounced with concurrent work. The badge counts active sessions across providers. Attention takes priority; the star transitions to a success mark only when all observed sessions are complete. Interrupted or uncertain tasks never become a false success mark.

Hovering for 180 ms opens a compact glance with task counts and the most relevant attention state. Clicking anywhere in the glance opens an unpinned detail panel with all agents, including recent results. The black surface grows first; text follows after a short delay, while the header symbols stay anchored. A 550 ms exit delay lets the pointer enter the panel, and dismissal verifies its actual position. Reused hosting views resynchronize hover state so crossing from the header into the glance cannot close it prematurely. Pinning requires the explicit pin button; clicking the star opens details without pinning. The panel closes when the pointer leaves unless explicitly pinned. Codex rows open the original chat using its validated source UUID. Other providers currently open their application. The app never needs focus just to show a badge. The expanded list scrolls for larger groups. Without a notch, the same controls occupy a compact strip below the menu bar. The app is now built for **arm64 only**; Intel is outside the product target.

An animated pulse trace sits on the left: slow at rest, faster while keep awake is active. Its speed changes smoothly, and Reduced Motion displays a static trace. A third, faster rhythm is used only after the power service confirms an active closed-lid lease. Click to keep the Mac awake until observed tasks finish (30 minutes if there are none), or hover for timed options. This is a **standard idle-sleep assertion**, not closed-lid mode. The display can sleep normally. The assertion has a macOS-enforced timeout, is process-owned, and is released when Lore exits. Lore also stops it when the session ends, battery reaches 20% while on battery, or thermal pressure is serious/critical. No persistent power preference is changed. Disabling the live island or manually sleeping the Mac ends the standard keep-awake session. Timed sessions are never restored automatically at app launch.

The live monitor remains independent of historical indexing: discovery every ten seconds, appended JSONL bytes every two seconds off the main actor. Initial reads use a bounded 2 MiB tail plus identity metadata; partial lines wait for a newline, and replacements/truncations reset the reader. Unknown/quiet sessions turn gray after five minutes and disappear after thirty; the live reader buffers terminal states for 45 seconds, but the visible success mark lasts only six seconds. No prompts, responses or tool arguments are retained.

Signal coverage remains Codex task lifecycle and question tools, Claude Code explicit end-turn/question metadata, and activity-only signals for current Gemini CLI JSONL logs. Unrecorded permission dialogs and legacy Gemini JSON snapshots cannot provide complete live status.

**Pulse · Lid closed:** the dedicated Pulse page now includes an explicit administrator-approval flow using `SMAppService`, and separate 15-minute / 1-hour / 2-hour / 4-hour sessions, on battery or charger. The embedded service only accepts a signed, non-debuggable Lore client from the same team; it independently checks power-source availability, battery above 20% and thermal state. A root-owned recovery journal is written before any global sleep change, and the service restores sleep after expiry, client loss, missing heartbeats or failed safety checks. It refuses to take over an existing global sleep override. On this development Mac, the user explicitly approved registration on 2026-09-12: the service is running, its authenticated status call responds, and the closed-lid lease remains off. The initial registration did not activate a lease; a controlled battery-powered physical test was subsequently performed on 2026-09-13 and restored normal sleep. The read-only ~/Code grant is also saved. The first battery-powered physical check confirmed 52 seconds of continuous sampling with the lid closed; a separate quit-Lore check restored sleep. Longer runs remain to be validated. See [implementation, limitations and validation plan](Docs/ClosedLid-AppleSilicon.md).


### Quiet updates and stable interaction

A new task does not automatically open the notch. Newly observed attention requests and completions can show a four-second compact announcement containing the project and status. There is no sound and no focus activation. Launching or resuming monitoring does not replay old announcements. Existing user interaction takes priority: an open/pinned panel is not replaced by an announcement. Disable these notices in **Settings → Live island → Brief attention and completion updates**.

The expanded panel keeps the latest completed/stopped result per session for 20 minutes, up to 12 recent results, in memory only. These are outcomes observed while Lore is running, not a new persisted history database. The full Timeline remains separate. The success check disappears after six seconds even while the result remains available in Details.

Opening Details freezes the row order and membership independently of whether the panel is pinned. Status, project labels and elapsed time can update in place; missing live signals become uncertain instead of silently deleting a row. New tasks appear behind an explicit **update list** action, so they cannot shift a click target under the pointer. Closing and reopening uses fresh ordering, with attention first. **⇧⌘A** opens task details from Lore's menu as a keyboard alternative.

Attention copy distinguishes a recorded question from Claude Code's recorded plan-approval request. Only the kind of request is retained; question text and tool arguments remain ignored. Codex rows use `codex://threads/<source UUID>`, the route observed in the installed Codex app’s Copy Link implementation. IDs are retained as optional metadata in SwiftData and in transient live state; malformed IDs cannot become commands or arbitrary URLs. This is an observed local integration, not a documented stable public API. Other providers retain the explicitly labeled application fallback.

The pulse glance shows either the remaining timed minutes or “until tasks finish.” Its upper rhythm is capped at three times the resting rhythm, with smooth acceleration and Reduced Motion support. Closed-lid authorization and activation live in Settings → Closed-lid mode.


### Local update validation

The installer keeps the app bundle directory and, for an unchanged helper, its executable inode intact. Replacing an executing helper's file invalidates subsequent signature checks even when its replacement has identical bytes; UI-only updates now preserve that file via a temporary hard link. A changed privileged binary still needs a managed service restart and separate release validation. The XPC error bridge is nonisolated and resumes once even when an error, reply and timeout race; regression tests cover background-queue errors and late completion. No code-signing requirement was relaxed.


## Reliability and navigation — 2026-09-13

- Today keeps the original square activity calendar. Daily session and commit counts are clipped to the chosen day; a period ending exactly at midnight does not appear on the next day. Opening a period shows observed time and links to its project and Codex chat.
- SwiftData’s optional source-ID migration was verified on a copy of the local store; the backup is in `build/Backups/Before-20260913.store`. No source logs or projects are altered.
- `swift run LoreDiagnostics --audit-sessions` reports aggregate provider counters and valid chat-link counts without Git access or conversation output. `--validate-store PATH` opens a disposable database copy to verify migration and relationships.
- Settings has an explicit three-minute closed-lid validation action. It checks the readable lid sensor, requests a bounded lease, samples with a continuous clock, and restores sleep after reopening, expiry or cancellation. Battery operation is permitted with the same battery/thermal guards; a test is distinct from a normal session. A sampling gap of three seconds or more makes the result inconclusive. The last report contains only timestamps, timing aggregates and restoration status at `~/Library/Application Support/Lore/last-lid-test.json`.
- Normal UI updates preserve an unchanged running helper’s executable inode. If the helper binary changes, the installer now refuses to replace it while its service runs: remove its registration in Lore, update, then register it again. Re-registration on this Mac reused the existing developer approval; no signing check is bypassed.


## Pulse and personalization

Pulse is the shared keep-awake feature in the sidebar, menu bar and heartbeat panel. Stay awake uses a native idle-sleep assertion; Lid closed uses the signed system service. Fixed durations of 15/30 minutes or 1/2/4 hours are available; Stay awake also supports until observed agents finish. The pulse click starts the chosen defaults or stops the current mode. No preference change starts a session automatically. Hiding the notch only changes presentation; monitoring and Pulse remain available through the app and menu bar.

Appearance offers system/light/dark themes, violet/blue/mint/rose accents, compact activity rows, reduced animations, relaxed hover timing, and optional remaining Pulse time in the menu bar. These choices persist locally. The original square calendar and opaque black notch are preserved. A family of rounded vector glyphs covers activity, projects, Pulse and preferences; no downloaded icon library or raster generation is required.

The menu-bar window includes today's activity, shared Pulse controls, live/recent agents with chat links, and a native More menu for navigation, preferences, diagnostics and Quit. System-access management is on the Pulse page, and the physical-test report is in Diagnostics. The product no longer labels the feature experimental; the documented extent of physical validation is unchanged.


## Favorites, presets and keyboard access

Mark a project as a favorite from its detail view. Favorites appear first in Projects and in the menu-bar Favorites submenu. Pulse presets save a name, mode and duration; loading one changes the next setup without activating power. Saving the same name updates the existing preset. Choices stay in local preferences, not project files.

When Lore has keyboard focus: **⌥⌘P** starts/stops Pulse, **⌥⌘.** stops it, and **⇧⌘P** opens the Pulse page. These are application shortcuts, not system-wide hotkeys.

The open-core and future paid-feature split is still a proposal: see [OpenCore-Strategy.md](Docs/OpenCore-Strategy.md). No paid restriction or commercial license has been introduced.
