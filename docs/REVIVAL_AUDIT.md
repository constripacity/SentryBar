# SentryBar revival audit

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



**Read this first.** This project has never been compiled. Not once, not by anyone, not at any point during this revival. The work was done on a Linux machine with no Swift toolchain, no Xcode, no macOS and no Apple hardware. There is no build log, no test report, no profiling data, and no signed artifact.

Every statement below comes from reading Swift source and from two mechanical checks that operate on text, not on a compiler. Where a claim would require running something, this document says so instead of making the claim.

---

## 1. What this document is

An audit of the SentryBar repository as it stood at git `HEAD` (`90ad340`), written alongside a revival whose changes are, at the time of writing, entirely uncommitted in the working tree.

| Term | Meaning | How to obtain |
| --- | --- | --- |
| **HEAD** | the shipped code, before the revival | `git show HEAD:<path>` |
| **current** | the revived working tree | the file on disk |

SentryBar is a menu-bar utility that watches outbound network connections on macOS and tells the user when something looks unusual. It is a security tool in the sense that matters most: people install it in order to be told something true about their machine, and they will believe what it says. That framing drives the severity assigned below. A UI bug in a note-taking app is a UI bug. A monitor that reports "0 suspicious connections" when it in fact failed to read anything is telling its user a comforting lie.

## 2. How this audit was produced

1. **Read the source at HEAD** — every Swift file under `SentryBar/` and `SentryBarTests/`, plus `install.sh`, `project.yml`, `Casks/sentrybar.rb`, `.github/workflows/build.yml`, `README.md`, `CLAUDE.md`.
2. **Read the current tree and `git diff` for every modified file**, to establish what actually changed rather than what the README says changed.
3. **Ran a bracket-balance check** over all Swift files in both trees — a hand-written Swift lexer that understands `//` comments, nested `/* */` comments, `"strings"`, `"""multiline strings"""`, `#"raw strings"#`, escapes, and `\(interpolation)` (interpolation re-enters code, so brackets inside it are counted). Result: **41/41 balanced in the current tree, 37/37 at HEAD.**
4. **Ran a symbol cross-reference check** on the same lexer's comment- and string-stripped output. Result: **67 project types declared, 0 declared twice, 0 unresolved references**, after 29 residue names were hand-classified as platform symbols.
5. **Ran the repository's own new CI static checks by hand**, since CI has never executed. One fails — see F11.

Not done, and not possible here: no `swiftc`, `swift build`, `xcodebuild`, or `xcodegen`. No `xcodebuild test` — no test has been executed. No run of the app or of `lsof`/`nettop`/`ps`/`sysctl` on macOS. No `codesign`, no notarisation, no `brew audit`, no `shellcheck`.

A bracket-balance check is not a parse. A symbol cross-reference is not type checking. Both pass on a file full of type errors.

## 3. What worked at HEAD

The previous author's work should not be dismissed. Several things were genuinely sound and the revival kept them.

- **The architecture was right for the product.** MVVM with plain `Services` (no SwiftUI imports), `@MainActor` view models owning timers, `Task.detached` for blocking system calls. Nothing in the file layout had to be rearranged.
- **The decision to avoid a Network Extension was correct and was never fudged.** Reading the socket table means the app installs like a normal app and works on managed Macs.
- **`Shell.run` drained its pipe on a background queue.** The comment `// Read pipe data concurrently to avoid pipe buffer deadlock` sits on code that does the right thing. Whoever wrote it had hit the 64 KB pipe deadlock and fixed it properly — the single hardest thing about spawning subprocesses, already correct.
- **`unescapeLsof` was correct**, including the truncated and malformed cases. It was carried into the current tree essentially unchanged.
- **IPv6 was handled in the address parser**, using `lastIndex(of: ":")` and stripping `[...]` brackets. The obvious naive `split(separator: ":")` bug was already avoided.
- **`ConnectionRule` persistence was careful** — JSON at `~/Library/Application Support/SentryBar/rules.json` written `0600`, decode failure degrading to an empty rule set rather than a crash.
- **The kill path had guards at all** — `pid > 1`, a system-process deny list, a confirmation dialog. The guards were wrong (F4), but the author knew guards were needed.
- **136 test functions existed**, using RFC 3849 documentation addresses for IPv6 fixtures. They assert the wrong things in places (F8) and had never been run (F9), but the habit was there.

## 4. What was broken

### F1 — `Shell.run` executed a constructed string through `/bin/zsh`

`SentryBar/Utilities/ShellHelper.swift` (deleted in the revival). The whole service layer went through it:

```swift
process.executableURL = URL(fileURLWithPath: "/bin/zsh")
process.arguments = ["-c", command]
```

**(a) The security boundary was a comment.** The file's own header:

```swift
/// WARNING: Never interpolate user-supplied strings into the command parameter.
/// Only numeric types (Int, Int32, etc.) are safe to interpolate.
```

Correct, and at HEAD it was obeyed — the five call sites interpolate only an `Int32` PID and an `Int` limit. But the API's shape is `run(_ command: String)`: it invites a caller to build a string, and the data flowing through this service is process names read out of `lsof`, which is attacker-influenced text. The next person to write `Shell.run("kill -9 \(name)")` gets command execution, and nothing in the type system, the compiler or the test suite would object. A design where the unsafe thing is the natural thing and safety is maintained by discipline fails eventually.

**(b) `zsh -c` reads `~/.zshenv`.** A non-interactive `zsh -c` still sources `/etc/zshenv` and `$ZDOTDIR/.zshenv`. `Process` inherits the parent environment, and the tools were resolved through `PATH`, not by absolute path:

```swift
let output = Shell.run("lsof -i -n -P 2>/dev/null | grep ESTABLISHED")
```

So the security monitor's view of the network was supplied by whichever `lsof` came first on a `PATH` that a dotfile could rewrite. Anything able to write `~/.zshenv` — far short of what it takes to compromise a system — could feed SentryBar a fabricated, permanently clean socket table. For a tool whose entire output is "here is what your machine is connected to", that is the worst failure mode available: it does not break, it lies.

**(c) The timeout path leaked a child process and two descriptors.**

```swift
if completed.wait(timeout: .now() + timeout) == .timedOut {
    process.terminate()
    _ = readGroup.wait(timeout: .now() + 1)
    return ""
}
```

`terminate()` sends `SIGTERM` and returns. There is no `waitUntilExit()`, no escalation to `SIGKILL`, and the pipe handle is never closed. An `lsof` that hangs — a stalled NFS mount, a wedged interface — leaves a zombie and a leaked descriptor on *every* polling cycle, default every 5 seconds, in an app whose `CLAUDE.md` targets "under 30MB RSS".

**(d) Output was unbounded and errors were discarded.** `readDataToEndOfFile()` has no cap, and `process.standardError = FileHandle.nullDevice` threw away the one thing that could explain a failure.

### F2 — Failure was indistinguishable from safety

`Shell.run` returns `""` on every failure path — spawn failure, timeout, non-zero exit, missing binary:

```swift
do {
    try process.run()
} catch {
    return ""
}
```

`getConnections()` passed that to the parser, which returned `[]`. `NetworkViewModel` published `[]`, `suspiciousCount` computed to `0`, and the UI drew an empty list with no warning.

The user sees the same screen whether their Mac has no outbound connections or SentryBar completely failed to look. No state anywhere in the app distinguishes the two. Silence is the tool's all-clear signal, and silence was also its error handling. The `2>/dev/null` inside the command string discarded `lsof`'s own diagnostics before they could reach a `stderr` that was already going to `/dev/null`.

### F3 — `lsof` output was parsed by counting whitespace columns

`NetworkService.parseLsofOutput`:

```swift
let parts = line.split(separator: " ", omittingEmptySubsequences: true)
guard parts.count >= 9 else { return nil }
...
let protocolType = String(parts[7]).uppercased().contains("TCP") ? "TCP" : "UDP"
```

Fixed indices into a whitespace split of a human-readable table. `lsof`'s default output is column-aligned, so a wide value in any earlier column shifts every later one, and any field containing a space splits in two. `guard parts.count >= 9` then drops the row.

The consequence is a blind spot the monitor never reports: an unparseable row is `compactMap`'d away — not logged, not counted, not surfaced. A connection SentryBar failed to parse and a connection that does not exist are, again, the same thing to the user.

The parser also carried branches for a missing state field and for `LISTEN`, both unreachable — the shell pipeline had already applied `| grep ESTABLISHED`. Dead code that looks like coverage is worse than absent code, because a reader takes it for handling.

### F4 — Terminating a process raced PID reuse and reported success wrongly

`NetworkService.killProcess(pid:)`:

```swift
let owner = Shell.run("ps -p \(pid) -o user= 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
guard !owner.isEmpty, owner != "root" else { return false }

let result = Shell.run("kill \(pid) 2>&1")
return !result.contains("Operation not permitted")
```

**(a) Time-of-check to time-of-use.** The owner is read in one subprocess and the signal sent in a second, later one. In between, the target may exit and its PID be reused. Two `zsh` spawns and a `ps` is a wide window — milliseconds, not microseconds — and PID reuse is not exotic on a busy Mac. Whatever holds the number when the second command runs is what gets signalled. The check does not protect the kill; it protects a process that may no longer exist.

**(b) The ownership test is the wrong test.** `owner != "root"` permits signalling every non-root account: `_mdnsresponder`, `_windowserver`, `daemon`, another human user. The question that matters is "do I own this?", not "is this not root?".

**(c) Success is inferred from a string.** `kill` fails with "No such process" and other messages; only "Operation not permitted" is matched, so every other failure is reported as success. `NetworkViewModel` then acts on it:

```swift
let success = await self.networkService.killProcess(pid: pid)
if success {
    await MainActor.run {
        self.connections.removeAll { $0.pid == pid }
    }
}
```

A failed termination makes the connection vanish from the UI while the process keeps running. The user is shown, and will reasonably believe, that they stopped it. Nothing reports the failure.

### F5 — The suspicion heuristic flooded, trusted a spoofable string, and missed the real case

`NetworkConnection.evaluateSuspicion(processName:remotePort:remoteAddress:)`:

```swift
if suspiciousPorts.contains(remotePort) { return true }

if let port = Int(remotePort), port > 49152, !isKnownProcess(processName) {
    return true
}
```

**The false positives.** The second rule flags any connection above port 49152 from a process not on a hard-coded list. On a real Mac that is WebRTC and QUIC traffic, game servers, CDNs on ephemeral ports, every Homebrew binary, every language runtime, every app released after the list was written. The list holds roughly 60 names; the world has more applications than that. A monitor that raises a hundred alarms a day for normal behaviour trains its user to dismiss alarms, leaving them worse off than with no tool at all — they now have a false sense of coverage as well.

**The trust is unauthenticated.** `isKnownProcess` ends:

```swift
return knownApps.contains(name) || systemProcesses.contains(name)
```

`name` comes from `lsof`, which reports the process's own command name. No signature check, no bundle identifier, no path. Naming a binary `Safari`, `node` or `curl` puts it on the allowlist. The same string drives `canKill = !NetworkConnection.systemProcesses.contains(processName)`, so a binary named `launchd` also becomes un-killable in the UI. An allowlist keyed on an attacker-chosen string is not an allowlist.

**The false negatives.** The port list is folklore — 4444, 1337, 31337, 5555, 6666, 8888. Nothing actually trying to hide uses them. Real exfiltration goes out over 443 to a plausible-looking host, and by construction this heuristic can never flag that: 443 is neither in `suspiciousPorts` nor above 49152. The tool is best at catching the one adversary who is not trying.

**Local traffic was not distinguished from external.** `remoteAddress` was accepted as a parameter and never examined. A printer at `192.168.1.30` and an unknown host in another country were treated identically.

### F6 — Alerts: suppressed meant deleted, and deduplication was by PID

There *was* rate limiting at HEAD — a 60-second cooldown per alert type. It was not deduplication, and the difference matters.

**(a) A suppressed alert is lost permanently.** `sendSuspiciousAlert` returns early inside the cooldown:

```swift
if let lastTime = lastSuspiciousAlertTime, Date().timeIntervalSince(lastTime) < notificationCooldown {
    return
}
```

The caller does not retry, and unconditionally advances its dedup state (`self.previouslySeenPIDs = currentPIDs`). So a genuinely new suspicious connection appearing 5 seconds after an unrelated one is discarded, and because its PID is now recorded, it is never raised again. The cooldown does not delay the alert. It deletes it.

**(b) Deduplication by PID hid new destinations from known processes.**

```swift
let newUnclassifiedSuspicious = classified.filter {
    $0.userClassification == nil && $0.heuristicSuspicious && !self.previouslySeenPIDs.contains($0.pid)
}
```

Once a process has been seen once, every subsequent connection it makes — anywhere, on any port — is filtered out for the life of that PID. A long-running process that opens a suspicious connection after SentryBar has already seen it is never reported. That is exactly the behaviour of a persistent implant. Conversely a process that reconnects with a fresh PID re-alerts every time, so one real-world condition both under- and over-reports depending on irrelevant details.

**(c) The bandwidth path marked alerts sent that were never sent.**

```swift
bandwidthAlertedProcesses.insert(process.processName)
sendBandwidthAlert(processName: process.processName, bytes: process.totalBytes)
```

The insert precedes a call that can return early on its own cooldown. The process is then recorded as alerted and skipped indefinitely — until it drops below the threshold, which sustained exfiltration will not do.

**(d) Notification identifiers were unique per delivery.** `identifier: "suspicious-\(UUID().uuidString)"` prevents Notification Center from replacing the previous notification, so repeats stack in the tray instead of updating in place.

**(e) There was no severity, no snooze, no per-condition identity, and no record of suppression.** A user whose SentryBar went quiet had no way to learn whether nothing was happening or the cooldown was eating everything.

### F7 — `install.sh` installed an unverified binary and deleted the working copy first

Advertised in the README as a `curl … | bash` one-liner. Its substance:

```bash
DMG_URL="https://github.com/${REPO}/releases/latest/download/${APP_NAME}.dmg"
curl -fsSL "${DMG_URL}" -o "${TMP_DMG}"
hdiutil attach "${TMP_DMG}" -nobrowse -quiet
```

- **No verification of any kind** — no checksum, no signature, no notarisation check, not even a size check. This is the installer for a security tool and it installs whatever arrives.
- **`rm -rf` before the copy.** `rm -rf "${INSTALL_DIR}/${APP_NAME}.app"` runs before `cp -R`, so a `cp` that fails on a full disk leaves the user with no SentryBar at all.
- **The mount point is assumed, not obtained.** `MOUNT_POINT="/Volumes/SentryBar"` is hard-coded while `hdiutil attach` is called without `-mountpoint`. If a volume of that name is already mounted, `hdiutil` mounts the image at `/Volumes/SentryBar 1` and the script copies the app from the pre-existing volume, then detaches it.
- **No platform or version check**, and no mention that the build is unsigned — so the user's first experience after a successful install is Gatekeeper refusing to open it, with no explanation.

### F8 — What the tests asserted

The 136 test functions at HEAD were real tests of real functions, but many of them asserted that the defective behaviour above was correct, which means they would have actively resisted fixing it:

```swift
func testHighPortUnknownProcessIsSuspicious() {
    XCTAssertTrue(NetworkConnection.evaluateSuspicion(
        processName: "mystery_app", remotePort: "50000", remoteAddress: "1.2.3.4"
    ))
}
```

That is F5's false-positive generator, pinned as a requirement. `testKnownProcessSafari`, `testKnownProcessDocker` and the rest similarly encode the name-based allowlist as intended behaviour rather than as the unauthenticated trust it is.

Structural gaps: **nothing tested a failure path** (no coverage of `Shell.run` returning `""`, a timeout, a missing tool — the whole F2 class is untested by construction); **nothing tested `killProcess`**, the most dangerous function in the codebase, which could not easily be tested because it reached out to two shells; **nothing tested the alerting logic** — `NetworkViewModel` had no test file, so all of F6 was unexercised; and **the parser fixtures were written by the parser's author from memory of `lsof`'s format** rather than from captured output, so the two agree with each other regardless of whether either matches `lsof`.

### F9 — CI never ran the tests

`.github/workflows/build.yml` at HEAD has one job: checkout, select Xcode, install xcodegen, `xcodegen generate`, `xcodebuild build`, then a tag-gated archive and release. There is no `xcodebuild test` anywhere in the file. Roughly a thousand lines of tests sat in the repository while every push and pull request built the app and ignored them.

### F10 — The "136 tests, all passing" claim

`CLAUDE.md` states, under "Testing":

> ### Current Coverage (136 tests, all passing)

The count is accurate as a count of declarations: `grep -E '^\s*func test'` over the ten test files at HEAD returns exactly 136. **"All passing" is fabricated.** There is no evidence anywhere in the repository that the suite was ever executed. CI did not run it (F9), so no run history exists; no result bundle, coverage report or log is committed; and the same file sixty lines earlier says `# Run tests (127 unit tests)` — two different totals in one document, which is what an unverified number looks like.

That claim predates this revival and was not written as part of it. It is called out because it is the most misleading line in the repository: it tells the next maintainer a green baseline exists, and it does not.

To be equally plain about the present: **this revival has not run the suite either.** The current tree's 138 test functions are 138 functions that exist.

### F11 — The revival's own new CI static check fails

Not a HEAD finding, but it belongs here because it is exactly what "never executed" conceals, and it was found by executing the check by hand. The new `static-checks` job asserts no shell is invoked outside `ProcessRunner`:

```bash
offenders=$(grep -rn "bin/sh\|bin/zsh\|bin/bash\|NSTask(" SentryBar/ --include='*.swift' || true)
if [ -n "$offenders" ]; then
  echo "::error::a shell is being invoked:"; echo "$offenders"; exit 1
fi
```

Run against the current tree it matches `SentryBar/Utilities/ProcessRunner.swift:6`, the doc comment that explains the `/bin/zsh -c` practice it replaced. The grep is not comment-aware, so the job would fail on the very commit that introduced it. The other two checks in that job pass: `Process()` appears only in `ProcessRunner.swift`, and `project.yml` and the cask both say `0.8.0`.

### F12 — The Homebrew cask had drifted

`Casks/sentrybar.rb` pinned `version "0.6.0"` and a hand-maintained `sha256 "37ac9e5f…"` while `project.yml` said `MARKETING_VERSION: "0.7.0"`. Nothing checked the pair, so `brew install sentrybar` fetched a release a minor version behind what the repository considered current. The file also carries `license :mit`, which is not a stanza in the current Cask DSL; `brew audit` was never run here, so that is a reading, not a verified failure.

## 5. What could not be checked, and why

This section is the point of the document. Everything below is unknown, and no amount of reading changes it.

**Nothing was compile-checked.** There is no Swift toolchain here. These classes of defect are invisible to both checks that were run, and any would stop a build: type errors, wrong argument labels, missing or extra parameters; protocol conformances that do not hold (`ConnectionFingerprint` as a `Codable` dictionary key, `AlertSeverity: Comparable`, the tuple comparison `($0.severity, $0.lastSeen) > ($1.severity, $1.lastSeen)` in `AlertEngine.currentAlerts`); Swift concurrency and actor-isolation errors, of which `NetworkViewModel` has many crossings between `@MainActor`, `Task.detached` and non-isolated services; availability errors against the macOS 13 target; non-exhaustive `switch` statements over the new enums; and ambiguity from `formatBytes`/`formatRate` moving to `ProcessRunner.swift` as free functions.

**No test has run.** Not one, in either tree. The 138 test functions in the current tree have never been compiled, let alone executed. Statements in this repository of the form "the tests cover X" mean "there is a function whose name says X".

**Every macOS API call is unproven.** None of the following has been observed working: `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID, pid)` and the `kinfo_proc` field access in `NetworkService.processInfo(pid:)` — in particular `info.kp_proc.p_comm` rebound to `CChar` with capacity `MAXCOMLEN + 1`, and `info.kp_eproc.e_ucred.cr_uid`, whose exposure to Swift under exactly those names is untested; `kill(2)` via the `Darwin` module; `SMAppService.mainApp.register()`; `UNUserNotificationCenter` delivery and the authorization request in `SystemViewModel`; the IOKit power-source calls in `BatteryService`; and `MenuBarExtra` with `.menuBarExtraStyle(.window)`.

**Tool output formats are assumed, not observed.** The new parser targets `lsof -i -n -P -F pcnPT` and assumes `f` records delimit per-socket entries within a process record. If `lsof` does not emit `f` for that field selection, several sockets belonging to one process would collapse into one. No `lsof` was run. The absolute paths in `SystemTool` (`/usr/sbin/lsof`, `/usr/bin/nettop`, `/bin/ps`, `/usr/sbin/sysctl`) were not checked against a real macOS filesystem; if any is wrong, `isAvailable` returns false and that reading silently becomes `.unavailable`.

**No signing, no notarisation, no certificate.** No Apple Developer account exists for this project. Nothing has been signed, stapled or submitted. The `codesign --verify` branch in `install.sh` has never executed, and the cask's `zap` paths have never been checked against a real installation.

**Nothing was measured.** No memory figure, no CPU figure, no timing, no battery impact. `CLAUDE.md`'s "under 30MB RSS" target is an aspiration nobody has tested. Any performance number anywhere in this repository is an estimate.

**The shell script was not linted or run.** `install.sh` has not been executed against a real release, `shellcheck` has not been run, and the checksum flow it depends on has never produced or consumed a real `.sha256` file.

## 6. Residual concerns in the revived tree

Found by reading the current code. Not HEAD findings — things a reader should know remain true after the revival.

1. **The baseline writes to disk on the main thread on every refresh.** `NetworkViewModel.refresh()` calls `self.baseline.observe(external)` inside `await MainActor.run { … }`, and `ConnectionBaseline.observe` ends with `save()`, a full JSON encode and atomic write. With the default 5-second interval and a 20,000-entry cap, that is a full encode-and-write on the main thread every five seconds. Unmeasured, but structurally wrong for a tool whose stated goal is to be light.
2. **`reset()` and `forget(process:)` are unreachable from the UI.** Both are declared on `ConnectionBaseline` and tested; neither is called from any view or view model. `README.md` nevertheless tells the user they can throw the baseline away with "`Reset baseline` in Settings". That control does not exist in the code.
3. **The snooze surface is unreachable.** `AlertEngine.snooze(key:for:)`, `snooze(type:for:)`, `unsnooze`, `acknowledge`, `isSnoozed`, `currentAlerts` and `unacknowledgedCount` are declared and tested; no view calls any of them.
4. **`baselineFindings` is published and never consumed** by any view.
5. **`previouslySeenPIDs` is dead state** — `NetworkViewModel` still assigns it and nothing reads it.
6. **`ConnectionBaseline.isWarmedUp` and `learningProgress` read `startedLearning` outside the serial queue** that guards every other access. Benign in practice, inconsistent with the rest of the type.
7. **`evaluateSuspicion` still exists**, deprecated and returning `false`, with no callers. Whether `@available(*, deprecated)` warns at its own unused declaration is a compiler question that has not been asked.

## 7. Inventory

Counts are mechanical: `find … -name '*.swift'` for files, `grep -E '^\s*func test'` for test functions.

### Files

| | HEAD | current | delta |
| --- | ---: | ---: | ---: |
| Swift files, application (`SentryBar/`) | 27 | 29 | +2 |
| Swift files, tests (`SentryBarTests/`) | 10 | 12 | +2 |
| **Swift files, total** | **37** | **41** | **+4** |
| Lines of Swift, application | — | 4,499 | |
| Lines of Swift, tests | — | 1,362 | |
| Lines of Swift, total | 4,558 | 5,861 | +1,303 |

Added: `SentryBar/Models/ConnectionBaseline.swift`, `SentryBar/Models/MonitorAlert.swift`, `SentryBar/Utilities/ProcessRunner.swift`, `SentryBarTests/AlertEngineTests.swift`, `SentryBarTests/ConnectionBaselineTests.swift`. Deleted: `SentryBar/Utilities/ShellHelper.swift`.

### Test functions that exist

**Existing is not passing.** None of these has been compiled or executed.

| Test file | HEAD | current |
| --- | ---: | ---: |
| AlertEngineTests | — | 15 |
| BandwidthServiceTests | 18 | 18 |
| BatteryInfoTests | 6 | 6 |
| ConnectionBaselineTests | — | 18 |
| ConnectionRuleTests | 12 | 12 |
| MenuBarIconOptionTests | 4 | 4 |
| NetworkConnectionTests | 29 | 10 |
| NetworkServiceTests | 28 | 16 |
| NotificationLogTests | 11 | 11 |
| ThermalInfoTests | 5 | 5 |
| UpdateServiceTests | 5 | 5 |
| UtilitiesTests | 18 | 18 |
| **Total** | **136** | **138** |

`NetworkConnectionTests` fell from 29 to 10 because the tests pinning the hard-coded allowlist and the high-port rule were deleted with the behaviour they asserted. `NetworkServiceTests` fell from 28 to 16 for the same reason: the column-index parser's fixtures went with the column-index parser.

### Static check results

| Check | HEAD | current |
| --- | --- | --- |
| Bracket/brace/paren balance (comment- and string-aware) | 37/37 balanced | 41/41 balanced |
| Project types declared | 50 | 67 |
| Types declared more than once | 0 | 0 |
| Cross-file references resolving to a project declaration | 34 | 44 |
| References neither declared nor a known platform symbol | 0 | 0 |

Both checks are text-level. Neither is a compiler, and passing them says nothing about whether this code builds.
