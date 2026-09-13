# Pulse: implementation and validation

Pulse is Lore's keep-awake feature for Apple Silicon Macs. It offers standard idle-sleep prevention and a separate lid-closed mode, on battery or charger.

## Completed hardware checks

The first instrumented lid-closed check was completed on **13 September 2026**, on an Apple Silicon Mac running macOS 26.6.2.

| Check | Observed result |
| --- | --- |
| Power source | Battery, without a charger |
| Time with lid detected closed | 52.40 seconds |
| Longest interval between samples | 1.095 seconds |
| Missing sensor samples | None |
| Local command execution while closed | Successful |
| Normal sleep after the check | Restored; `SleepDisabled = 0` |
| Quit Lore during a separate active session | Normal sleep restored when the client disconnected |

The user did not notice the coding task stopping and did not need to enter a password after reopening. The physical state of the built-in display while the lid was closed was not visually confirmed. Lore did not modify the user's lock or authentication settings.

These are completed checks, not a claim that no hardware testing has occurred. Longer sessions and additional Mac/macOS combinations still need broader coverage.

## Standard mode

`KeepAwakeController` owns a native `PreventUserIdleSystemSleep` assertion with a timeout. The assertion is released when stopped or when Lore exits. Standard mode allows display sleep and does not claim to prevent lid-triggered system sleep. [Apple's assertion documentation](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)

## Lid-closed mode

The signed service in `Helper/` is registered through `SMAppService` with user approval. Its fixed XPC API supports status, begin, heartbeat and end; it does not accept shell commands or arbitrary filesystem paths.

- Both peers require the expected signing identifier and matching Apple signing team, with no `get-task-allow` entitlement.
- The helper accepts a session only when the power source and battery can be read, battery is above 20%, and thermal state is acceptable.
- A session lasts at most four hours. Heartbeats cannot extend its original deadline.
- The helper refuses to take over a global sleep override already owned by another utility.
- A root-owned recovery journal is written before changing the sleep setting.
- It restores normal sleep on expiry, client disconnection, missing heartbeats, low battery or excessive thermal pressure. Failed restoration keeps the journal and is retried.
- The app sends a heartbeat every ten seconds; the helper's timeout is thirty seconds, checked every five seconds.
- Startup recovery restores a recorded previous session before new work is accepted. Pulse does not automatically reactivate at app launch.

The backend invokes only fixed `/usr/bin/pmset` commands, with a bounded subprocess timeout. `disablesleep` changes global sleep behavior; it is not a per-app assertion. The mechanism and its wider effects were investigated using [Apple's PowerManagement source](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m) and [IOPMrootDomain](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOPMrootDomain.cpp). Coordination with other sleep utilities is necessarily limited by that global setting.

## Installation and updates

System access is managed from the **Pulse** page. Unsigned/ad-hoc builds cannot enable the privileged service. No password, private signing key or sudoers rule is stored in the repository.

UI-only updates preserve an unchanged running helper's executable inode, keeping its signature verification valid. When the helper binary changes, the installer refuses to replace it while the service runs. Stop the session, remove the registration, install the build, then enable system access again. On the development Mac this reused the existing approval.

## Repeating the physical check

**Diagnostics → Validate on this Mac** starts a three-minute test. Close the lid for 30–60 seconds on a ventilated surface, then reopen it. The test reads `AppleClamshellState` from IOKit and uses a continuous clock to detect gaps in execution. A sampling gap of three seconds or more makes its result inconclusive.

The result is saved locally at `~/Library/Application Support/Lore/last-lid-test.json`. It contains timing aggregates, the initial power source and restoration status, not conversations. An awake Mac does not by itself prove that a particular network request or AI task completed.

Battery/thermal thresholds, deadlines, ownership, failed restoration and startup recovery are also covered by tests with an injected backend. Automated tests do not deliberately drain the battery or overheat the Mac. An active Mac should not be carried in an enclosed bag.
