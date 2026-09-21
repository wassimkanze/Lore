# Integration formats and behavior

Lore reads metadata from local tool history. These formats can change, so parsers are defensive and incomplete data stays unavailable rather than being invented.

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


## Claude Code and Gemini CLI integrations

Added on 2026-09-10. The indexer now accepts a collection of `AIProviderIntegration` implementations. Every provider uses namespaced stable session IDs, so equal source IDs from different agents cannot collide. A session without a resolvable project retains its own activity blocks labeled “Unassigned project”; it does not create a fictional project. Nearby sessions from different agents in a known project share the same activity grouping.

**Claude Code:** reads only the main `~/.claude/projects/<project>/*.jsonl` files. Two real sessions were found on this Mac, produced by versions 2.1.255 and 2.1.260. Allowed metadata is `sessionId`, `cwd`, timestamps, `message.id`, model and usage counters. Repeated assistant blocks with the same message ID are collapsed using the greatest observed counter values. Input includes uncached input, cache reads and cache creation; cached input reports reads only. This normalizes the cache convention to Lore's existing input-inclusive representation. Prompts, attachments, title records, tool results and response content are ignored. Nested subagent logs are deliberately excluded because they can reuse the parent's session ID; aggregate subagent accounting needs separate validation.

Lore opens validated Claude Code UUIDs through Claude Desktop's installed `claude://resume?session=…` route. Codex uses its validated `codex://threads/…` route. Gemini Desktop currently declares no compatible per-session route, so Lore opens the app without claiming that it selected a particular CLI session. Values read from session logs are never used as arbitrary URLs.

**Gemini CLI:** supports legacy `~/.gemini/tmp/<project>/chats/session-*.json` and current `.jsonl` files. The parser was implemented against the [official recording types](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingTypes.ts), [record loader](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/chatRecordingService.ts) and [project registry](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/config/projectRegistry.ts). It decodes session identity, timestamps, model and token metadata; repeated message IDs replace earlier snapshots. JSONL metadata updates, checkpoints and rewind records are supported. Counts reflect the remaining recorded history after a rewind, not deleted requests or an invoice. Gemini thought tokens are counted as output; cached tokens remain a subset of input. Optional tool-specific token counters are not folded into totals. Legacy JSON reads are bounded to 32 MiB; JSONL uses the existing streaming limit. Malformed messages are skipped where the surrounding JSON is valid, and an invalid file cannot block other sessions.

Project roots come from the adjacent `.project_root` marker or the explicit path-to-slug mapping in `~/.gemini/projects.json`. A recorded directory is used only if its SHA-256 matches `projectHash`; extra workspace directories are not assumed to be the project root. Changes to project-mapping files invalidate cached session metadata. Authentication, settings, account databases and arbitrary cached browser content are never read by these integrations.

On this Mac, **Gemini desktop was detected but no `.gemini` CLI directory was present**. The inspected desktop store schemas exposed settings/account state, not usable session history. Lore reports this distinction in Settings and does not manufacture Gemini activity, inspect credentials, query private Google endpoints or install the CLI. The Gemini reader is covered by synthetic fixtures but cannot yet be validated against real local Gemini CLI sessions on this Mac.

New tests cover Claude usage deduplication and cache normalization, Gemini JSON/JSONL updates and rewinds, malformed data, cross-provider identity, discovery failure isolation, missing projects, project-map cache invalidation, duplicate-free reindexing and preservation of source fixture bytes.



## Grouped live island and keep awake

One animated Lore star to the right of the notch now represents all AI providers. It stays dim and still at rest; a wave travels through its branches while tasks work, becoming more pronounced with concurrent work. The badge counts active sessions across providers. Attention takes priority; the star transitions to a success mark only when all observed sessions are complete. Interrupted or uncertain tasks never become a false success mark.

Hovering for 180 ms opens a compact glance with task counts and the most relevant attention state. Clicking anywhere in the glance opens an unpinned detail panel with all agents, including recent results. The black surface grows first; text follows after a short delay, while the header symbols stay anchored. A 550 ms exit delay lets the pointer enter the panel, and dismissal verifies its actual position. Reused hosting views resynchronize hover state so crossing from the header into the glance cannot close it prematurely. Pinning requires the explicit pin button; clicking the star opens details without pinning. The panel closes when the pointer leaves unless explicitly pinned. Codex and Claude Code rows open the original session using validated source UUIDs. Gemini retains an explicitly labeled application fallback because its installed desktop app exposes no compatible session route. The app never needs focus just to show a badge. The expanded list scrolls for larger groups. Without a notch, the same controls occupy a compact strip below the menu bar. The app is now built for **arm64 only**; Intel is outside the product target.

An animated pulse trace sits on the left: slow at rest, faster for standard keep-awake, and fastest for a confirmed lid-closed session. Clicking starts the saved Pulse mode and duration or stops the current session; hovering exposes the shared controls. Hiding the notch does not stop Pulse. Standard idle-sleep assertions and the privileged lid-closed service are separate implementations described in [the Pulse documentation](ClosedLid-AppleSilicon.md). Sessions are not automatically reactivated at app launch.

The live monitor remains independent of historical indexing: discovery every ten seconds, appended JSONL bytes every two seconds off the main actor. Initial reads use a bounded 2 MiB tail plus identity metadata; partial lines wait for a newline, and replacements/truncations reset the reader. Unknown/quiet sessions turn gray after five minutes and disappear after thirty; the live reader buffers terminal states for 45 seconds, but the visible success mark lasts only six seconds. No prompts, responses or tool arguments are retained.

Signal coverage remains Codex task lifecycle and question tools, Claude Code explicit end-turn/question metadata, and activity-only signals for current Gemini CLI JSONL logs. Unrecorded permission dialogs and legacy Gemini JSON snapshots cannot provide complete live status.

**Pulse · Lid closed:** the dedicated Pulse page now includes an explicit administrator-approval flow using `SMAppService`, and separate 15-minute / 1-hour / 2-hour / 4-hour sessions, on battery or charger. The embedded service only accepts a signed, non-debuggable Lore client from the same team; it independently checks power-source availability, battery above 20% and thermal state. A root-owned recovery journal is written before any global sleep change, and the service restores sleep after expiry, client loss, missing heartbeats or failed safety checks. It refuses to take over an existing global sleep override. On this development Mac, the user explicitly approved registration on 2026-09-12: the service is running, its authenticated status call responds, and the closed-lid lease remains off. The initial registration did not activate a lease; a controlled battery-powered physical test was subsequently performed on 2026-09-13 and restored normal sleep. The read-only ~/Code grant is also saved. The first battery-powered physical check confirmed 52 seconds of continuous sampling with the lid closed; a separate quit-Lore check restored sleep. Longer runs remain to be validated. See [implementation, limitations and validation plan](ClosedLid-AppleSilicon.md).


### Quiet updates and stable interaction

A new task does not automatically open the notch. Newly observed attention requests and completions can show a four-second compact announcement containing the project and status. There is no sound and no focus activation. Launching or resuming monitoring does not replay old announcements. Existing user interaction takes priority: an open/pinned panel is not replaced by an announcement. Disable these notices in **Appearance → Live island → Brief attention and completion updates**.

The expanded panel keeps the latest completed/stopped result per session for 20 minutes, up to 12 recent results, in memory only. These are outcomes observed while Lore is running, not a new persisted history database. The full Timeline remains separate. The success check disappears after six seconds even while the result remains available in Details.

Opening Details freezes the row order and membership independently of whether the panel is pinned. Status, project labels and elapsed time can update in place; missing live signals become uncertain instead of silently deleting a row. New tasks appear behind an explicit **update list** action, so they cannot shift a click target under the pointer. Closing and reopening uses fresh ordering, with attention first. **⇧⌘A** opens task details from Lore's menu as a keyboard alternative.

Attention copy distinguishes a recorded question from Claude Code's recorded plan-approval request. Only the kind of request is retained; question text and tool arguments remain ignored. Codex rows use `codex://threads/<source UUID>`, the route observed in the installed Codex app’s Copy Link implementation. Claude Code uses the installed app's `claude://resume?session=<source UUID>` route. IDs are retained as optional metadata in SwiftData and in transient live state; malformed IDs cannot become commands or arbitrary URLs. These are observed local integrations, not documented stable public APIs.

The pulse glance shows either the remaining timed minutes or “until tasks finish.” Its upper rhythm is capped at three times the resting rhythm, with smooth acceleration and Reduced Motion support. System access and lid-closed sessions are managed on the Pulse page.


### Local update validation

The installer keeps the app bundle directory and, for an unchanged helper, its executable inode intact. Replacing an executing helper's file invalidates subsequent signature checks even when its replacement has identical bytes; UI-only updates now preserve that file via a temporary hard link. A changed privileged binary still needs a managed service restart and separate release validation. The XPC error bridge is nonisolated and resumes once even when an error, reply and timeout race; regression tests cover background-queue errors and late completion. No code-signing requirement was relaxed.
