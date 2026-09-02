# SentryBar revival changelog

> **Re-measured after the final round of fixes.** The transcripts below were
> produced part-way through the revival. Three further defects were then fixed:
> the new CI `static-checks` job failed on ProcessRunner's own doc comment
> (its grep was not comment-aware) and is now
> `scripts/swift_static_checks.py`, a committed checker that strips comments,
> keeps string literals, and also balances brackets; `ConnectionBaseline.reset()`
> and `forget(process:)` were tested but unreachable from any view, while the
> README promised a "Reset baseline" control in Settings — Settings now has a
> **Network baseline** section that lists what has been learned and calls both;
> and `CLAUDE.md`'s "136 tests, all passing" was replaced with a measured
> inventory that states plainly that none has been executed.
>
> Re-measured at the shipped tree:
>
> - `python3 scripts/swift_static_checks.py` — **41 Swift files: brackets
>   balanced, no shell outside ProcessRunner**. Mutation-tested: an injected
>   `Process()`, an injected `"/bin/zsh"` literal and an unbalanced brace are
>   each caught; a `/bin/zsh` mentioned in a comment is correctly not.
> - `grep -c "func test" SentryBarTests/*.swift` — **142 test functions**.
>
> **Still never compiled. Still no test executed.** That does not change.



## 0.6.0 → 0.8.0 — 2026-09-02

**Read this before anything else in this file.**

**Nothing here has been compiled.** This release was written on Linux with no Swift toolchain, no Xcode, no macOS and no Apple hardware. `swiftc` was never invoked. `xcodebuild` was never invoked. `xcodegen` was never invoked. **No test has been executed** — not the 138 that exist now, and not the 136 that existed before. Nothing has been code-signed or notarised, and no signing certificate exists for this project.

Every item below describes a change made to source text. Whether that text builds, runs, or behaves as described on a Mac is unknown. Read **Verification** and **Not verified** at the end before trusting anything above them.

On the version numbers, since the repository disagreed with itself: at `HEAD`, `Casks/sentrybar.rb` said `0.6.0`, `project.yml` said `MARKETING_VERSION: "0.7.0"`, and `CLAUDE.md` said "Version: 0.7.0". This release sets `0.8.0` in both `project.yml` and the cask, and CI now fails if they diverge again.

Full findings: [`REVIVAL_AUDIT.md`](./REVIVAL_AUDIT.md).

---

## Security and correctness

### The shell is out of the data path

`SentryBar/Utilities/ShellHelper.swift` is deleted. Every system tool now runs through `SentryBar/Utilities/ProcessRunner.swift`, which takes a `SystemTool` case and an argument array:

```swift
ProcessRunner.run(.lsof, ["-i", "-n", "-P", "-F", "pcnPT"], timeout: 6)
```

There is no `/bin/zsh -c`, so no character in any argument is special and there is nothing to quote. This matters beyond hygiene: `zsh -c` sources `/etc/zshenv` and `~/.zshenv` even non-interactively, and the old code resolved `lsof`, `ps` and `nettop` through the inherited `PATH`. Anything able to write a dotfile could therefore substitute the binary that told SentryBar what the machine was connected to. `SystemTool` names each tool by absolute path (`/usr/sbin/lsof`, `/usr/bin/nettop`, `/bin/ps`, `/usr/sbin/sysctl`, `/usr/sbin/ioreg`, `/usr/bin/pmset`), and `ProcessRunner` sets a fixed environment rather than inheriting one:

```swift
process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
```

The old file's defence was a comment — *"WARNING: Never interpolate user-supplied strings into the command parameter"* — attached to an API whose only parameter was a string. That instruction was obeyed at the time. It was still the wrong shape, because the unsafe thing was the easy thing.

### Failures are values, not empty strings

`ToolResult` is `.success(String)`, `.timedOut(after:)`, `.failed(status:stderr:)` or `.unavailable(tool:)`, and carries a `userFacingMessage`. `NetworkService.lastResult` and `BandwidthService.lastResult` expose the most recent outcome, `NetworkViewModel.readingProblem` publishes it, and `NetworkMonitorView.readingProblemBanner(_:)` draws it above the list.

Previously `Shell.run` returned `""` for a spawn failure, a timeout, a missing binary and a non-zero exit alike; the parser turned `""` into `[]`; the UI drew an empty list. A user could not distinguish "your Mac has no outbound connections" from "SentryBar failed to look". For a tool whose all-clear signal is silence, that is the most dangerous defect in the codebase, which is why it is listed above the injection fix.

### The subprocess is reaped, bounded, and killed if it will not stop

`ProcessRunner.run` escalates on timeout — `terminate()`, wait one second, then `kill(process.processIdentifier, SIGKILL)` — then calls `waitUntilExit()` and closes both pipe handles. The old timeout path called `terminate()` and returned immediately, never reaping the child and never closing the pipe, so a hung `lsof` left a zombie and a leaked descriptor behind on every refresh (default: every five seconds).

`readBounded(_:limit:)` caps stdout at 4 MB and stderr at 64 KB, replacing an unbounded `readDataToEndOfFile()`. Both pipes are drained concurrently — which the old code already did correctly for stdout — and stderr is captured rather than sent to `FileHandle.nullDevice`, so a failure can say why.

### `lsof` is parsed from field output, not by counting columns

`NetworkService.parseLsofOutput` (whitespace split, fixed indices, `guard parts.count >= 9`, `parts[7]` for the protocol) is replaced by `parseLsofFieldOutput(_:includeListening:)`, which consumes `lsof -F pcnPT`: one `<tag><value>` per line, `p` opening a process record and `f` opening a socket record.

Column indices into an aligned human-readable table shift whenever a value is wide or contains a space, and the old parser dropped every row it could not index — silently, via `compactMap`, with no count and no banner. A connection SentryBar failed to parse looked exactly like a connection that did not exist.

The shell pipeline `| grep ESTABLISHED` is gone; state filtering happens in the parser, so the `LISTEN` and no-state branches that were unreachable behind that `grep` are now either live (`includeListening:`) or removed.

### Terminating a process no longer races PID reuse

`killProcess(pid:) -> Bool` is replaced by `terminate(pid:expectedName:) -> TerminateOutcome`.

The old version read the owner in one `zsh` and sent the signal in a second, later `zsh`. In between, the target could exit and its PID be reused, and the signal would land on whatever held the number. The new version reads owner and name together from the kernel process table in one call — `NetworkService.processInfo(pid:)` using `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID, pid)` — then calls `kill(2)` directly, with no subprocess in the path at all.

It also requires the caller to name the process it believes it is signalling:

```swift
guard info.name == expectedName else {
    return .refused(reason: "PID \(pid) is now \(info.name), not \(expectedName). ...")
}
```

The ownership test changed from `owner != "root"` — which permitted signalling `_mdnsresponder`, `daemon` and every other non-root account — to `info.uid == getuid()`.

Success is no longer inferred from a string. The old code returned `!result.contains("Operation not permitted")`, so "No such process" and every other failure was reported as success, and `NetworkViewModel` then removed the row from the list — showing the user a process they had not stopped as stopped. `TerminateOutcome` distinguishes `.signalled`, `.refused(reason:)` and `.failed(reason:)`; `NetworkViewModel.lastTerminateOutcome` publishes it; `NetworkMonitorView` presents the reason in an alert.

### The suspicion heuristic is gone, replaced by a local behavioural baseline

`NetworkConnection.evaluateSuspicion(processName:remotePort:remoteAddress:)` was:

```swift
if let port = Int(remotePort), port > 49152, !isKnownProcess(processName) {
    return true
}
```

Two problems, in opposite directions.

It flooded. Any connection above port 49152 from a process not on a hard-coded ~60-name list is WebRTC, QUIC, a game server, a CDN, a Homebrew binary, or an app released after the list was written. A monitor that raises a hundred false alarms a day teaches its user to ignore alarms.

And it trusted a string. `isKnownProcess` ended `return knownApps.contains(name) || systemProcesses.contains(name)`, where `name` is the command name reported by `lsof` — chosen by the process itself. No signature check, no bundle identifier, no path. Naming a binary `Safari` put it on the allowlist; naming it `launchd` also made it un-killable in the UI. Meanwhile the static port list (4444, 1337, 31337, …) covers exactly the adversary who is not hiding, while 443 to a plausible host — the actual case — could never be flagged.

`ConnectionBaseline` replaces it: it records `(process, /24 or /48 prefix, port)` fingerprints on disk, stays silent for a three-day learning period, and after that reports a combination it has not seen, with the count it is comparing against. `NetworkConnection.heuristicSuspicious` is filled in by the baseline after parsing rather than computed by the parser; the parser now makes no judgements at all.

`evaluateSuspicion` is retained, marked `@available(*, deprecated)` and returning `false`, so any caller missed by the refactor degrades to "not suspicious" rather than to the old flood. `isKnownProcess` and `suspiciousPorts` are deleted; a grep confirms no remaining references.

### Alerts deduplicate by condition, rate-limit globally, and are never silently dropped

`AlertEngine` (in `SentryBar/Models/MonitorAlert.swift`) replaces `lastSuspiciousAlertTime`, `lastBandwidthAlertTime`, `notificationCooldown` and `bandwidthAlertedProcesses` in `NetworkViewModel`.

The old cooldown did not defer an alert, it deleted one:

```swift
if let lastTime = lastSuspiciousAlertTime, Date().timeIntervalSince(lastTime) < notificationCooldown {
    return
}
```

The caller did not retry and unconditionally advanced its dedup state (`self.previouslySeenPIDs = currentPIDs`), so a genuinely new suspicious connection arriving inside another alert's 60-second window was discarded permanently.

Deduplication was also by PID:

```swift
let newUnclassifiedSuspicious = classified.filter {
    $0.userClassification == nil && $0.heuristicSuspicious && !self.previouslySeenPIDs.contains($0.pid)
}
```

Once a process had been seen once, every later connection it made — anywhere, on any port — was filtered out for the life of that PID. That is precisely the behaviour of a persistent implant, and precisely what the tool exists to catch.

And the bandwidth path recorded alerts it had not sent:

```swift
bandwidthAlertedProcesses.insert(process.processName)
sendBandwidthAlert(processName: process.processName, bytes: process.totalBytes)
```

The insert preceded a call that could return early on its own cooldown, after which the process was treated as already alerted indefinitely.

`AlertEngine` keys on the condition instead of the PID (`NetworkConnection.alertKey`, `"bandwidth:<process>"`, `"new:<fingerprint>"`), coalesces repeats into an occurrence counter, re-notifies only after `repeatInterval` (default 30 minutes), applies a global limit of `maxPerWindow` (default 6) per `windowLength` (default 5 minutes), and returns an `AlertDecision` for every raise — `.deliver`, `.coalesced`, `.snoozed`, `.rateLimited`, `.belowThreshold` — so a suppression is a recorded fact rather than a silent `return`.

Notification identifiers changed from `"suspicious-\(UUID().uuidString)"` — a fresh UUID per delivery, which stops Notification Center replacing the previous one — to the stable alert key.

### `install.sh` verifies the download and no longer deletes your working copy first

The old script fetched `releases/latest/download/SentryBar.dmg`, mounted it and copied it into `/Applications` with no checksum, no signature check and no notarisation check — advertised in the README as a `curl … | bash` one-liner, for a security tool. It ran `rm -rf "${INSTALL_DIR}/${APP_NAME}.app"` *before* the copy, so a failed `cp` left the user with nothing, and it hard-coded `MOUNT_POINT="/Volumes/SentryBar"` while calling `hdiutil attach` without `-mountpoint`, so a pre-existing volume of that name would be the one copied from and then detached.

The new script resolves the latest tag through the GitHub API, downloads the DMG and its published `.sha256`, and refuses to continue if the checksum is absent or does not match:

```bash
if [ "${EXPECTED}" != "${ACTUAL}" ]; then
    fail "checksum mismatch — the download does not match what was published. ..."
fi
```

It mounts with an explicit `-mountpoint` inside a `mktemp -d` working directory cleaned up by an `EXIT` trap, stages the new copy before moving the old one aside, and restores the previous version if the move fails. It checks `uname -s` is Darwin and that the macOS major version is at least 13. Finally it runs `codesign --verify` and, when that fails, prints the `xattr -dr com.apple.quarantine` command rather than running it:

> You are being told this rather than having the script do it for you: a script that silently disarms Gatekeeper on your behalf is exactly the pattern you should refuse from anyone, including this one.

### CI runs the tests

`.github/workflows/build.yml` at `HEAD` had one job: checkout, select Xcode, install xcodegen, generate, `xcodebuild build`, and a tag-gated archive and release. There was no `xcodebuild test` anywhere in the file. Roughly a thousand lines of tests were in the repository and every push built the app and ignored them.

The workflow now has three jobs: `test` (running `xcodebuild test` before the Release build), `static-checks`, and a `release` job gated on both. **This workflow has never run.**

## Added

- **`SentryBar/Models/ConnectionBaseline.swift`** — `ConnectionFingerprint`, `BaselineEntry`, `BaselineFinding`, `ConnectionBaseline`. A deterministic, entirely local model of which processes normally reach which destinations. Addresses are generalised to a /24 (IPv4) or /48 (IPv6) prefix so a CDN answering from a different host each time stays one entry rather than being permanently new. Persisted to `~/Library/Application Support/SentryBar/network-baseline.json` via write-to-sibling then `replaceItemAt`, with `0700` on the directory and `0600` on the file. Entries older than `retention` (60 days) are pruned; the store is capped at `maxEntries` (20,000), evicting least-recently-seen first. A corrupt file is discarded rather than half-loaded.
- **`SentryBar/Models/MonitorAlert.swift`** — `AlertSeverity`, `MonitorAlert`, `AlertDecision`, `AlertEngine`. `MonitorAlert` carries a `suggestion`, on the principle that an alert with no available action is noise.
- **`SentryBar/Utilities/ProcessRunner.swift`** — `SystemTool`, `ToolResult`, `ProcessRunner`, plus `formatBytes`/`formatRate` relocated unchanged from the deleted `ShellHelper.swift`.
- **`NetworkConnection.isPrivateAddress(_:)` and `isExternal`** — RFC 1918, loopback, link-local and IPv6 ULA/link-local detection. Only external connections are baselined; a link to a printer at `192.168.1.30` is not an anomaly. The old model never examined `remoteAddress` at all.
- **`NetworkConnection.notableProtocolPorts` and `protocolNote(forPort:)`** — a short table of ports where an unencrypted or administrative protocol is in use (Telnet, FTP, POP3, SMB, VNC, RDP, SSH), surfaced at `.info` severity as a statement of fact rather than an accusation.
- **`NetworkConnection.alertKey`** — stable identity across refreshes, which is what makes deduplication possible at all.
- **`NetworkViewModel.baselineStatus`** and `baselineStatusRow` in `NetworkMonitorView` — the UI now says "Still learning what is normal (42%). Nothing is flagged as new until this finishes" instead of implying confidence it has not earned.
- **`SentryBarTests/ConnectionBaselineTests.swift`** — 18 test functions covering warm-up silence, fingerprint generalisation, per-process and per-port distinctness, retention pruning, the entry cap, round-tripping through disk, corrupt-file recovery and file permissions.
- **`SentryBarTests/AlertEngineTests.swift`** — 15 test functions covering first delivery, coalescing, the repeat interval, the sliding rate-limit window, snoozing by key and by type, the severity floor, and the requirement that unrelated conditions not suppress each other.
- **CI `static-checks` job** — asserts no shell is invoked outside `ProcessRunner`, that `Process()` appears only in `ProcessRunner.swift`, and that `project.yml` and `Casks/sentrybar.rb` agree on the version.
- **Release artifacts** — the release job publishes `SentryBar.dmg.sha256` alongside the DMG (`install.sh` refuses to install without it) and rewrites the cask's `version` and `sha256` from the artifact it just built.

## Changed

- `NetworkService.getConnections()` takes `includeListening: Bool = false` and records `lastResult`.
- `NetworkService.getTopProcesses(limit:)` no longer pipes through `head`; it runs `ps` directly and applies `prefix(limit)` in Swift.
- `NetworkService.parsePsOutput` reconstructs commands containing spaces from everything between the PID and the CPU column, and drops rows that do not parse instead of coercing them with `Int32(parts[0]) ?? 0`.
- `BandwidthService.measureBandwidth()` goes through `ProcessRunner`, records `lastResult`, and clamps the measured duration with `max(duration, 0.1)` so a near-zero wall-clock reading cannot produce an absurd rate.
- `NetworkViewModel` gains `baseline`, `alerts`, `baselineFindings`, `readingProblem` and `lastTerminateOutcome`; `killProcess(pid:)` becomes `terminate(connection:)`; `checkBandwidthAlerts` clears alerts for processes that drop back under the threshold, so the next occurrence is genuinely new.
- `NetworkMonitorView`'s confirmation dialog now says what will happen ("SentryBar will ask … to quit"), states that only processes you own are signalled and that the PID is re-checked first, and a second alert reports the outcome when it fails.
- `Casks/sentrybar.rb` — `version` `0.6.0` → `0.8.0`; the hand-maintained `sha256` becomes `:no_check` with a comment saying the release workflow rewrites it; `depends_on macos: ">= :ventura"` added (MenuBarExtra needs 13); `verified:` added to the URL; a `caveats` block explains the Gatekeeper prompt and states that SentryBar cannot block traffic; the `zap` preference path is corrected from `com.sentrybar.plist` to `com.sentrybar.SentryBar.plist`; `license :mit`, not part of the Cask DSL, is removed.
- `project.yml` — `MARKETING_VERSION` `0.7.0` → `0.8.0`.
- `README.md` — rewritten around the tradeoff it had been eliding. It now states in the first screen that SentryBar **watches and warns and cannot block a connection**, that polling misses short-lived connections, and that LuLu is the tool for blocking. A comparison table places it against Stats, Sniffnet, LuLu and bandwhich, including where those are better.

## Removed

- **`SentryBar/Utilities/ShellHelper.swift`** — the `Shell` enum and `Shell.run(_:timeout:)`. Its two formatting helpers moved to `ProcessRunner.swift` unchanged.
- **`NetworkConnection.isKnownProcess(_:)`** and the ~60-name `knownApps` allowlist inside it — trust keyed on a string the observed process controls.
- **`NetworkConnection.suspiciousPorts`** — the folklore port list.
- **`NetworkService.parseLsofOutput(_:)`** — the column-index parser.
- **`NetworkService.killProcess(pid:)`** — the two-shell, string-matching kill.
- **`NetworkViewModel.sendSuspiciousAlert(count:note:processName:)`, `sendBandwidthAlert(processName:bytes:)`, `lastSuspiciousAlertTime`, `lastBandwidthAlertTime`, `notificationCooldown`, `bandwidthAlertedProcesses`** — superseded by `AlertEngine`.
- **19 test functions** in `NetworkConnectionTests` and 12 in `NetworkServiceTests` that asserted the deleted behaviour was correct — among them `testHighPortUnknownProcessIsSuspicious`, which pinned the false-positive generator as a requirement.

## Verification

Everything in this section was actually executed in this environment. Nothing else was.

### 1. Bracket, brace and parenthesis balance — run, passed

A hand-written Swift lexer that understands `//` line comments, nested `/* */` block comments, `"strings"`, `"""multiline strings"""`, `#"raw strings"#` with any number of hashes, backslash escapes, and `\(interpolation)` — interpolation re-enters code, so brackets inside it are counted, and brackets inside string and comment text are not.

```
current tree: checked 41 .swift files: 41 balanced, 0 unbalanced
HEAD tree:    checked 37 .swift files: 37 balanced, 0 unbalanced
```

The checker was validated against a deliberate negative control before being trusted: a file with an unclosed `{`, a string containing `)( } `, and a multiline string containing `} ) ]`. It reported exactly one failure — `unclosed '{' opened on line 1` — and passed the file whose stray brackets were all inside string literals. It exits non-zero on an imbalance.

### 2. Symbol cross-reference — run, passed after hand-classifying the residue

Operating on the same lexer's comment- and string-stripped output, so a name appearing only in prose or in a string literal is not counted as a reference. It collects every `class`/`struct`/`enum`/`protocol`/`actor`/`typealias`/`extension` name declared in the project and every capitalised identifier referenced, and reports the difference.

```
current tree:
  declared in the project : 67 type names
  distinct capitalised references found: 207
  references resolving to a project declaration: 67 (44 used outside their declaring file)
  references matched against the platform-SDK allowlist: 144
  unresolved: 0
  type names declared more than once: 0

HEAD tree:
  declared in the project : 50 type names
  distinct capitalised references found: 176
  references resolving to a project declaration: 50 (34 used outside their declaring file)
  unresolved: 0
  type names declared more than once: 0
```

The first pass on the current tree reported **29 unresolved names**. All 29 were inspected by hand and are platform symbols, not project symbols: nine IOKit C functions and constants (`IOServiceMatching`, `IOPSCopyPowerSourcesInfo`, `IO_OBJECT_NULL`, …); three Core Graphics types (`CGFloat`, `CGPoint`, `CGSize`); SwiftUI containers missing from the initial allowlist (`ForEach`, `LazyVGrid`, `GridItem`, `TabView`, `StrokeStyle`); Foundation and AppKit types (`HTTPURLResponse`, `JSONSerialization`, `IndexSet`, `NSNumber`, `NSApplication`, `NSPasteboard`, `NSObjectProtocol`, `NSTemporaryDirectory`, `CFTypeRef`); `ProcessInfo.ThermalState`, whose outer name the regex strips; the `Self` keyword; the generic parameter `Wrapped` in `Extensions.swift`; and the module name `SentryBar` from `@testable import SentryBar`. The allowlist was extended with those 29 names and the check re-run to zero. That classification was manual, and it is the weakest step in this section.

### 3. Dangling references to deleted symbols — run, passed

`grep` across all Swift files for each removed symbol:

| Symbol | Remaining references |
| --- | --- |
| `Shell.run` | 1, in a doc comment in `ProcessRunner.swift` |
| `ShellHelper` | 0 |
| `isKnownProcess` | 0 |
| `suspiciousPorts` | 0 |
| `killProcess` | 0 |
| `parseLsofOutput` | 0 |
| `evaluateSuspicion` | 1, its own deprecated declaration |

### 4. The repository's own CI static checks, run by hand — one fails

| Check | Result |
| --- | --- |
| `Process()` only in `ProcessRunner.swift` | passes |
| `project.yml` version matches the cask | passes (both `0.8.0`) |
| No shell invoked outside `ProcessRunner` | **fails** |

The failing check is:

```bash
offenders=$(grep -rn "bin/sh\|bin/zsh\|bin/bash\|NSTask(" SentryBar/ --include='*.swift' || true)
```

It matches `ProcessRunner.swift:6`, the doc comment explaining the `/bin/zsh -c` practice this release removed. The grep is not comment-aware, so the `static-checks` job would fail on the commit that introduced it. This is reported rather than fixed because the brief for this document was to report what the checks actually produce.

### 5. Counting — run

`find … -name '*.swift'` and `grep -E '^\s*func test'`:

| | HEAD | current |
| --- | ---: | ---: |
| Swift files (app / tests / total) | 27 / 10 / 37 | 29 / 12 / 41 |
| Lines of Swift | 4,558 | 5,861 |
| **Test functions that exist** | **136** | **138** |

The 136 at HEAD is exactly the number `CLAUDE.md` claims, so that count is right; "all passing" in the same line is supported by nothing in the repository, and HEAD's CI never ran the suite. Existing is not passing.

## Not verified

Read this as the true status of this release.

- **The project has never been compiled.** No `swiftc`, no `swift build`, no `xcodebuild`, no `xcodegen generate` — in this revival or at any earlier point in the repository's history that left evidence. Every type error, wrong argument label, missing conformance, actor-isolation violation, availability error and non-exhaustive `switch` in this codebase is still there, undetected. A bracket-balance check is not a parse and a symbol cross-reference is not type checking; a file full of type errors passes both.
- **No test has ever been executed.** Not the 138 that exist now, not the 136 that existed before. `xcodebuild test` has never run here. The test names in this document describe intent, not results.
- **The new CI workflow has never run.** One of its three static checks is known to fail (Verification §4). The `test`, `release`, archive, DMG, checksum and cask-rewrite steps are unexecuted text.
- **Nothing is signed or notarised, and no certificate exists.** There is no Apple Developer account for this project. `codesign` has never been run, nothing has been submitted to Apple's notary service, and no stapled ticket exists. Gatekeeper will refuse these builds. The `codesign --verify` branch in `install.sh` has never executed.
- **Every macOS API touched here is unproven.** In particular: `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID, pid)` and the `kinfo_proc` member access in `NetworkService.processInfo(pid:)` — `info.kp_proc.p_comm` rebound to `CChar` with capacity `MAXCOMLEN + 1`, and `info.kp_eproc.e_ucred.cr_uid` — which have never been compiled against a real Darwin module map; `kill(2)` via the `Darwin` import; `SMAppService.mainApp.register()`; the `UNUserNotificationCenter` authorization request in `SystemViewModel` and every notification delivery depending on it; the IOKit power-source calls in `BatteryService`; and `MenuBarExtra` with `.menuBarExtraStyle(.window)`.
- **Tool output formats are assumed, not observed.** `lsof` was never run. The new parser assumes `lsof -F pcnPT` emits `f` records delimiting each socket within a process record; if it does not, several sockets belonging to one process would collapse into one and connections would be lost. The absolute paths in `SystemTool` were not checked against a real macOS filesystem — if one is wrong, `isAvailable` is false and that reading silently becomes `.unavailable`. `nettop`'s output format was likewise not observed.
- **`install.sh` has not been run or linted.** No `shellcheck`, no execution against a real GitHub release, no `.sha256` file ever produced or consumed. Its `sw_vers`, `hdiutil`, `shasum` and `codesign` paths are untested.
- **The cask has not been audited.** `brew audit`, `brew style` and `brew install --cask` were never run. Removing `license :mit` and adding `depends_on macos:` are reasoned from documentation, not from a passing audit.
- **Nothing has been measured.** No memory figure, no CPU figure, no timing, no battery impact, no benchmark. Any performance number anywhere in this repository is an estimate. `CLAUDE.md`'s "under 30MB RSS" target has never been tested. In particular, `ConnectionBaseline.save()` runs on the main thread on every refresh — a full JSON encode and atomic write of up to 20,000 entries, every five seconds at the default interval — and that cost is unmeasured.
- **Several new capabilities have no way to reach them.** `ConnectionBaseline.reset()` and `forget(process:)` are declared and tested and called from no view, though `README.md` tells the user "`Reset baseline` in Settings" exists. `AlertEngine.snooze`, `unsnooze`, `acknowledge`, `isSnoozed`, `currentAlerts` and `unacknowledgedCount` are likewise unreachable from the UI, and `NetworkViewModel.baselineFindings` is published and never read. These are gaps between the documentation and the code, not build failures.
- **The three-day learning period has never elapsed anywhere**, because the code has never run. Whether the baseline's warm-up, generalisation and pruning behave sensibly against real traffic is entirely unknown; the only evidence is synthetic fixtures in unexecuted tests.
- **No screenshot exists.** `README.md` contains a placeholder asking for one.
- **No macOS 13 device, VM or CI runner has ever loaded this code.**
