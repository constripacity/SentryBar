# The next 20 commits

## Where this repository actually stands

**None of this code has ever been compiled.** The revival that produced the
current tree was done on Linux, with no Swift toolchain, no Xcode and no macOS.
Verification consisted of three things: a bracket-balance lexer that understands
string and comment context, a symbol cross-reference pass, and reading. That is
enough to catch a missing brace or a call to a function that does not exist. It
is not enough to catch a type error, an actor-isolation error, a missing
`@available`, an SF Symbol that does not exist on macOS 13, or a runtime crash.

So treat every claim below as a claim about *source*, not about *behaviour*.
Nothing here has been observed running. In particular:

- The 138 `func test…` cases across twelve files in `SentryBarTests/` have never
  been executed. Any pass/fail count written down is fabricated — `CLAUDE.md`
  says "136 tests, all passing", and that sentence has no basis.
- `xcodegen generate` has never been run against `project.yml`, and the CI
  workflow has never completed a run in its current form.
- No DMG has been produced from this tree, and nothing has been signed or
  installed.

What *is* solid is the shape of the code. `ProcessRunner.swift` replaced string
shell commands with argv execution. `NetworkService` parses `lsof -F` field
output instead of scraping columns. The hard-coded 60-app allowlist and the
"high port is suspicious" rule are gone, replaced by `ConnectionBaseline` and
`AlertEngine`. Those are the right designs.

What is missing is that most of that new machinery is not connected to anything
a user can see, and several parts of it defeat themselves. `AlertEngine`'s
snooze, acknowledge and severity-floor APIs are referenced only by tests.
`NetworkViewModel.baselineFindings` is published and read by no view. Protocol
notes are raised at `.info` and dropped by a `.notice` floor, so the feature that
replaced the deleted heuristic reaches the user through no path at all. Every
control in the Settings tab writes to `UserDefaults` through an `@AppStorage`
property on a plain class, which does not publish, so the panel does not update
and "Launch at Login" may never call `SMAppService`. The baseline's three-day
warm-up is measured on wall-clock time rather than time spent observing.

The ordering below reflects that. Commit 1 is the only one that can go first,
because until the thing compiles nothing else can be believed.

---

## Commit 1 — Build and test on a real Mac, and stop the test bundle from launching the app

This is the gate. Run `xcodegen generate`, then `xcodebuild build` and
`xcodebuild test`, and fix whatever the compiler says. Expect real errors: the
tree was written blind. The highest-risk sites are `NetworkViewModel.refresh()`
(lines 141–225), which uses `async let` over a `@MainActor`-isolated
`self.networkService` from inside `Task.detached` and `await`s two synchronous
methods; `NetworkService.processInfo(pid:)` (lines 226–240), which rebinds
`kinfo_proc.kp_proc.p_comm` to `CChar` with `MAXCOMLEN + 1`; and
`AlertEngine.currentAlerts`, which compares `(AlertSeverity, Date)` tuples with
`>`.

The test target compounds this. `project.yml` sets `TEST_HOST` to
`SentryBar.app/Contents/MacOS/SentryBar`, so running the tests boots the real
menu-bar app: `SentryBarApp.init()` constructs `SystemViewModel` and
`NetworkViewModel`, both of which call `startMonitoring()` from their
initialisers, which starts `Timer`s and begins spawning `lsof`, `ps` and
`nettop`, and `SystemViewModel.requestNotificationPermission()` puts up an
authorization request on a headless CI runner. Tests cannot be trusted while
that is happening underneath them. Guard the app's startup work on
`ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"]`.

Note also that `SentryBarApp` builds `SettingsViewModel()` and
`ConnectionRuleStore()` twice — once in the property initialisers on lines 5–6,
once in `init()` on lines 12–13 — so the rules file is read from disk twice at
launch and the first pair of objects is discarded.

**Files:** `project.yml`, `SentryBar/App/SentryBarApp.swift`,
`SentryBar/ViewModels/NetworkViewModel.swift`,
`SentryBar/ViewModels/SystemViewModel.swift`, `.github/workflows/build.yml`,
whatever the compiler names.

**Done when**
- [ ] `xcodegen generate && xcodebuild build -scheme SentryBar` succeeds locally with zero errors.
- [ ] `xcodebuild test -scheme SentryBar` runs to completion and prints a test count; that count is written into `CLAUDE.md`, replacing the invented "136 tests, all passing".
- [ ] No `Timer` is scheduled and no subprocess is spawned when `XCTestConfigurationFilePath` is set — asserted by a test that checks `NetworkViewModel` has no active timer under test.
- [ ] `SettingsViewModel` and `ConnectionRuleStore` are each constructed exactly once at launch, asserted by a counter in a debug build or by removing the duplicate property initialisers.
- [ ] The CI job passes on `macos-14`, including the `xcode-select` line for Xcode 16.2 — or that line is changed to a version the runner image actually ships.

---

## Commit 2 — Make `AppSettings` publish, so the Settings tab stops being write-only

`AppSettings` (`SentryBar/Models/AppSettings.swift`) is an `ObservableObject`
whose twelve properties are all `@AppStorage`. `@AppStorage` is a
`DynamicProperty`; it only participates in the update graph when it is declared
inside a `View`, `App` or `Scene`. Declared on a plain class it still reads and
writes `UserDefaults`, but it never touches `objectWillChange`.

`SettingsViewModel.appSettings` is furthermore a plain `var`, not `@Published`.
So when `SettingsView` writes through `$viewModel.appSettings.showNotifications`
(line 89) the binding mutates a property on a class instance — it does not
reassign `appSettings`, and nothing publishes. The value lands in `UserDefaults`
and the panel does not redraw. Toggles keep showing their old state, and the
`Text("\(Int(viewModel.appSettings.refreshIntervalSystem))s")` readout beside
each slider does not follow the drag, until some unrelated publisher
(`updateAvailable`, or `ruleStore.rules`) happens to force a redraw.

`StatusIconView` has the same problem from the other side: it takes
`appSettings` as a plain `var` (line 6) and renders
`Image(systemName: appSettings.menuBarIcon)`, so choosing a different menu-bar
icon in Settings changes nothing until something else redraws the label.

**Files:** `SentryBar/Models/AppSettings.swift`,
`SentryBar/ViewModels/SettingsViewModel.swift`,
`SentryBar/Views/SettingsView.swift`, `SentryBar/Views/StatusIconView.swift`,
`SentryBarTests/` (new `AppSettingsTests.swift`).

**Done when**
- [ ] `AppSettings` no longer uses `@AppStorage`; each property is a `@Published` value backed by an injectable `UserDefaults`, and mutating any one of them fires `objectWillChange`.
- [ ] A test constructs `AppSettings(defaults:)` against a scratch suite, subscribes to `objectWillChange`, mutates `showNotifications`, and observes exactly one emission.
- [ ] A test asserts a value written through `AppSettings` is readable from the same `UserDefaults` suite under the key `com.sentrybar.showNotifications`, so existing users' preferences survive the change.
- [ ] `StatusIconView` observes `appSettings` rather than holding it as a plain `var`.
- [ ] `SettingsViewModel.resetToDefaults()` no longer needs its manual `objectWillChange.send()` and the key list on lines 38–51 is derived from `AppSettings` rather than duplicated by hand.

---

## Commit 3 — Make Launch at Login actually register, and say so when it fails

`SettingsView` line 39 binds a `Toggle` to `viewModel.appSettings.launchAtLogin`
and hangs `.onChange(of:)` off it to call `toggleLaunchAtLogin()`. After
commit 2 that will fire reliably; today it fires only when some other publisher
happens to re-evaluate the body, so the login item may never be registered at
all.

Even once it fires, `SettingsViewModel.toggleLaunchAtLogin()` (lines 23–34)
swallows the error: on failure it flips the stored boolean back and tells the
user nothing. `SMAppService.mainApp.register()` throws for reasons the user needs
to hear — most importantly that the app is not code-signed, which is the state
every current build is in (see commit 18). Nothing reconciles the stored boolean
with `SMAppService.mainApp.status` either, so if the user removes SentryBar from
Login Items in System Settings, the toggle keeps claiming it is on.

**Files:** `SentryBar/ViewModels/SettingsViewModel.swift`,
`SentryBar/Views/SettingsView.swift`, `SentryBar/Models/AppSettings.swift`,
`SentryBarTests/SettingsViewModelTests.swift` (new).

**Done when**
- [ ] `SettingsViewModel` exposes `launchAtLoginStatus` derived from `SMAppService.mainApp.status`, refreshed when the panel appears, and the toggle renders from that rather than from the stored boolean.
- [ ] A failed `register()` sets a published `launchAtLoginError` and the Settings tab renders it inline, naming code signing as a cause when `status == .notFound`.
- [ ] `SMAppService` is reached through a protocol so a test can inject a stub that throws, and a test asserts the toggle returns to off and the error string is non-nil.
- [ ] Toggling on, quitting and relaunching leaves the toggle on, verified by hand on a real Mac and recorded in the commit message.

---

## Commit 4 — Stop discarding baseline findings when the rate limiter fires

This is the worst bug in the new alerting path, and it silently destroys the
product's headline feature.

`ConnectionBaseline.observe(_:)` records a fingerprint and returns a
`BaselineFinding` for it in the same pass (`ConnectionBaseline.swift` lines
167–191). The next time that connection appears, `entries[fingerprint]` exists,
the loop `continue`s, and no finding is produced — ever again.

`NetworkViewModel.raiseConnectionAlerts` turns each finding into a
`MonitorAlert` and hands it to `AlertEngine.raise`, which delivers at most six
per five minutes. Anything beyond that returns `.rateLimited`, which
`deliver(_:)` (lines 395–419) handles by calling `logger(_:)` — a `print`
compiled out of release builds by `#if DEBUG`. On the next refresh
`alerts.retainOnly(keys:)` drops the held alert because the finding is not in
`live` any more.

So: a browser that reaches thirty new subnets in one refresh produces thirty
findings, six notifications, and twenty-four destinations that the user is never
told about and that the baseline now considers normal. The README promises
"a combination it has never seen is reported once". Today it is reported once
*or not at all*, decided by a rate limiter with no memory.

**Files:** `SentryBar/Models/ConnectionBaseline.swift`,
`SentryBar/Models/MonitorAlert.swift`,
`SentryBar/ViewModels/NetworkViewModel.swift`,
`SentryBarTests/AlertEngineTests.swift`,
`SentryBarTests/ConnectionBaselineTests.swift`.

**Done when**
- [ ] A suppressed alert is retained in a pending queue rather than dropped; `AlertEngine` exposes `heldAlerts` and `retainOnly(keys:)` does not evict a key that has never been delivered.
- [ ] A test raises 20 distinct `.notice` alerts inside one window, asserts 6 are delivered, and asserts the other 14 are still retrievable from `heldAlerts` afterwards.
- [ ] A test advances the clock past `windowLength` and asserts the held alerts drain in order rather than being lost.
- [ ] A test asserts that a finding whose alert was rate-limited still appears in the notification log, so the record exists even when the banner did not.
- [ ] `#if DEBUG print` is no longer the only record of a suppression.

---

## Commit 5 — Warm the baseline up on time spent observing, not on the calendar

`ConnectionBaseline.isWarmedUp` is
`Date().timeIntervalSince(startedLearning) >= learningPeriod` (line 134), and
`startedLearning` is stamped once, at first launch, and persisted.

That means the three-day warm-up passes whether or not SentryBar was running.
Install it, quit it, come back on Thursday: the baseline holds one refresh worth
of endpoints, `isWarmedUp` is true, and the next refresh reports essentially
every connection on the machine as a new destination. That is precisely the
alert flood the baseline was built to replace, arrived at from the other
direction. The same thing happens to anyone who uses a laptop intermittently, or
who leaves it closed over a weekend.

The fix is to accumulate observation, not elapsed time: count refreshes actually
performed, or distinct calendar days on which at least one observation was
recorded, and gate on both that and a minimum number of learned endpoints.
`learningProgress`, which the UI already shows in
`NetworkViewModel.baselineStatus`, should report the same measure.

**Files:** `SentryBar/Models/ConnectionBaseline.swift`,
`SentryBar/ViewModels/NetworkViewModel.swift`,
`SentryBarTests/ConnectionBaselineTests.swift`.

**Done when**
- [ ] `ConnectionBaseline` persists an observation counter and a set of distinct days observed, and `isWarmedUp` reads from those, not from `Date()`.
- [ ] A test creates a baseline, jumps `now` forward by 30 days without recording a single observation, and asserts `isWarmedUp == false`.
- [ ] A test records observations across three distinct simulated days and asserts `isWarmedUp == true`.
- [ ] `baselineStatus` reports observation progress, and the string it produces is asserted by a test.
- [ ] A baseline file written by the previous format loads without throwing and restarts its warm-up rather than declaring itself warm.

---

## Commit 6 — Put the alert engine in front of the user

`AlertEngine` implements severity, dedupe counters, per-key and per-type snooze,
acknowledgement, and a severity floor. Grepping the app target for
`currentAlerts`, `unacknowledgedCount`, `acknowledge(key:)`, `snooze(key:for:)`,
`snooze(type:for:)`, `unsnooze` and `isSnoozed` finds them in
`MonitorAlert.swift` and in `SentryBarTests/AlertEngineTests.swift` — and
nowhere else. `NetworkViewModel.baselineFindings` is `@Published` and read by no
view.

The Alerts tab renders `NotificationLog`, which stores only
`(type, title, body, timestamp)`, caps at 50 entries and lives entirely in
memory, so the history is empty on every launch. `MonitorAlert.suggestion` — the
"what you can do about it" string that the code comments call the difference
between an alert and noise — is folded into the notification body and never
shown in the app.

Meanwhile `README.md` states, under "Alerts that are worth reading", that alerts
are "**Snoozable** per alert or per category, with a severity floor you set" and
that "Suppressions are written to the notification log". Neither is true. Either
the UI arrives or those sentences come out; this commit is the former.

**Files:** `SentryBar/Views/NotificationLogView.swift`,
`SentryBar/Models/NotificationLog.swift`, `SentryBar/Models/MonitorAlert.swift`,
`SentryBar/ViewModels/NetworkViewModel.swift`,
`SentryBar/ViewModels/SystemViewModel.swift`,
`SentryBar/Models/AppSettings.swift`, `SentryBar/Views/SettingsView.swift`.

**Done when**
- [ ] The Alerts tab lists `AlertEngine.currentAlerts` with severity symbol, `suggestion`, and the `repeatedLabel` count, above the historical log.
- [ ] Each live alert row has a working Snooze (1h / today / this category) and Acknowledge control, and snoozes persist across a relaunch.
- [ ] A "why am I not seeing alerts" section lists currently held and suppressed keys with the reason (`coalesced`, `rateLimited`, `snoozed`, `belowThreshold`).
- [ ] The severity floor is a setting in `AppSettings`, wired to `AlertEngine.minimumSeverity`, defaulting to the current `.notice`.
- [ ] `NotificationLog` persists to `~/Library/Application Support/SentryBar/` at mode `0600` and reloads on launch.
- [ ] `SystemViewModel`'s thermal and battery alerts go through `AlertEngine` instead of the `lastThermalAlertTime` / `lastBatteryAlertTime` pair and the 60-second `notificationCooldown` on lines 19–21, which is the exact mechanism `MonitorAlert.swift`'s own header says was replaced.

---

## Commit 7 — Make protocol notes reachable

`NetworkConnection.notableProtocolPorts` and `protocolNote(forPort:)` are what is
left after the "high port is suspicious" heuristic was deleted. They are the only
static signal the app still offers, and today they reach the user through no path
whatsoever.

`NetworkViewModel.raiseConnectionAlerts` raises them at `AlertSeverity.info`
(line 376). `AlertEngine`'s default `minimumSeverity` is `.notice`, so
`raise(_:)` returns `.belowThreshold` on line 142, and `deliver(_:)` handles that
case with a bare `break` — no notification, no log entry, nothing. And
`connectionDetailRow` in `NetworkMonitorView` renders `serviceLabel` and
`remoteAddress` but never `protocolNote`, so the note is absent from the list as
well.

The result is that a user with a Telnet session open, or an app authenticating
over unencrypted IMAP, is told nothing at all — even though the code contains a
carefully worded string explaining exactly that.

While here: `getConnections(includeListening:)` is never called with `true`, so
listening sockets are excluded everywhere in the app despite the parser and a
test supporting them. A process listening on a port is at least as interesting as
one making an outbound connection.

**Files:** `SentryBar/Views/NetworkMonitorView.swift`,
`SentryBar/ViewModels/NetworkViewModel.swift`,
`SentryBar/Models/NetworkConnection.swift`,
`SentryBar/Services/NetworkService.swift`,
`SentryBarTests/NetworkConnectionTests.swift`.

**Done when**
- [ ] `connectionDetailRow` shows `protocolNote` inline when it is non-nil, with the unencrypted-protocol note visually distinct from the neutral ones.
- [ ] A protocol-note alert either reaches the log or is visibly listed as suppressed by the severity floor; `deliver(_:)`'s `.belowThreshold` case no longer discards silently.
- [ ] The Network tab has a "show listening ports" control that passes `includeListening: true`, and listening rows are labelled as such rather than shown with a remote address of `*`.
- [ ] A test asserts a connection on port 23 produces a note containing "not encrypted" and that it survives into the view model's published connections.

---

## Commit 8 — Give the user control of the baseline

`README.md` line 104 tells the reader: "you can throw it away: `Reset baseline`
in Settings, or `forget(process:)` for one app that legitimately changed its
endpoints."

There is no Reset baseline in Settings. `ConnectionBaseline.reset(now:)` has zero
callers in the app target. `forget(process:)` has one caller, in
`ConnectionBaselineTests.swift`. `endpointCount(forProcess:)` has none at all.
The user has no way to inspect what has been learned, no way to correct it, and
no way to start over after an app legitimately changes its infrastructure — which
is the single most common reason a behavioural baseline goes wrong.

This matters more than a missing button, because the baseline is a file that
grows to 20,000 entries and shapes every alert for 60 days. A learned model the
user cannot see or edit is a model they cannot trust.

**Files:** `SentryBar/Views/SettingsView.swift`,
`SentryBar/Views/NetworkMonitorView.swift`,
`SentryBar/ViewModels/NetworkViewModel.swift`,
`SentryBar/Models/ConnectionBaseline.swift`.

**Done when**
- [ ] Settings has a Baseline section showing `knownEndpointCount`, the observation progress from commit 5, and the storage path.
- [ ] A "Reset baseline" button with a confirmation calls `reset()`, and a test asserts `knownEndpointCount == 0` and the warm-up restarts afterwards.
- [ ] The connection context menu gains "Forget what SentryBar learned about <process>", calling `forget(process:)`; a test asserts only that process's fingerprints are removed.
- [ ] The expanded app group shows `endpointCount(forProcess:)` so the user can see what the alert text is comparing against.
- [ ] `README.md` line 104 describes controls that exist.

---

## Commit 9 — Rebuild `ProcessRunner` on a non-blocking design

`ProcessRunner.run` (lines 81–166) waits by spinning:
`while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }`.
`BandwidthService.measureBandwidth()` calls it with `timeout: 15`, from inside a
`Task.detached`. That parks a cooperative-pool thread — of which there are as
many as you have cores — for up to fifteen seconds, doing nothing. Two or three
of those and the pool is starved and unrelated `await`s stop making progress.

There is also a lifetime bug on the timeout path. `readBounded` runs on a
concurrent `DispatchQueue`, blocking in `handle.availableData`. Line 148 waits
for the group with a two-second cap, and lines 150–151 then call `close()` on
both read handles whether or not the readers finished. If a reader is still
inside `availableData`, the handle is closed underneath it. The same two lines
also read `outData` and `errData`, which the reader closures write, without any
synchronisation once the group wait has timed out.

Rebuild it around `Process.terminationHandler` and `readabilityHandler`, or a
`DispatchSource` on the child, with an `async` entry point and a dedicated
serial queue for the process lifecycle. No `Thread.sleep`, no unsynchronised
shared `var`, no closing a descriptor another thread is reading.

**Files:** `SentryBar/Utilities/ProcessRunner.swift`,
`SentryBar/Services/NetworkService.swift`,
`SentryBar/Services/BandwidthService.swift`,
`SentryBarTests/ProcessRunnerTests.swift` (new).

**Done when**
- [ ] `ProcessRunner.run` is `async` and contains no `Thread.sleep`.
- [ ] A test runs `/bin/sleep 5` with `timeout: 0.5` and asserts `.timedOut` is returned within one second and that the child is reaped (`waitpid` reports no zombie).
- [ ] A test runs a tool producing more than `maxOutputBytes` and asserts the result is truncated at the limit and the process still exits.
- [ ] A test runs 20 concurrent invocations and asserts all complete, demonstrating no pool starvation.
- [ ] The whole test file passes under Thread Sanitizer with no reported races.

---

## Commit 10 — Make the refresh path safe under strict concurrency

`NetworkViewModel` is `@MainActor`, so `networkService`, `bandwidthService` and
`baseline` are main-actor-isolated stored properties. `refresh()` reaches all
three from inside `Task.detached` (lines 141–225), and `terminate(connection:)`
does the same on line 240. `NetworkService`, `BandwidthService` and
`ConnectionBaseline` are plain non-`Sendable` classes with mutable state —
`lastResult` on the first two, `entries` and `startedLearning` on the third.

`ConnectionBaseline` guards `entries` with `queue` in `observe`, `isKnown`,
`reset` and `forget`, but reads it unguarded in `knownEndpointCount` (line 144)
and `endpointCount(forProcess:)` (line 147), and reads `startedLearning`
unguarded in `isWarmedUp` and `learningProgress` — all of which the view calls
from the main actor while `observe` may be mutating from elsewhere.

Whether this compiles today is exactly the kind of question that cannot be
answered without a compiler. Whether it is correct is not in doubt: it is not.
Settle it by building the target with `-strict-concurrency=complete` and making
the services either actors or explicitly `Sendable` types with internal
synchronisation.

Also delete the two pieces of genuinely dead code here:
`previouslySeenPIDs` (assigned on line 199, read nowhere) and
`NetworkConnection.evaluateSuspicion`, which is deprecated, returns `false`, and
has no callers.

**Files:** `SentryBar/ViewModels/NetworkViewModel.swift`,
`SentryBar/ViewModels/SystemViewModel.swift`,
`SentryBar/Services/NetworkService.swift`,
`SentryBar/Services/BandwidthService.swift`,
`SentryBar/Models/ConnectionBaseline.swift`,
`SentryBar/Models/NetworkConnection.swift`, `project.yml`.

**Done when**
- [ ] `project.yml` sets `SWIFT_STRICT_CONCURRENCY: complete` and the target builds with zero concurrency warnings.
- [ ] Every read of `ConnectionBaseline.entries` and `startedLearning` goes through its queue or its actor.
- [ ] `previouslySeenPIDs` and `NetworkConnection.evaluateSuspicion` are absent from the source tree.
- [ ] A stress test drives `observe` from a background task while reading `knownEndpointCount` from the main actor for 1,000 iterations, and passes under Thread Sanitizer.

---

## Commit 11 — Stop polling when nobody is looking

`NetworkViewModel` and `SystemViewModel` each schedule a repeating `Timer` in
their initialiser and never stop it. `stopMonitoring()` exists on both and is
called by neither. Nothing observes whether the `MenuBarExtra` panel is open,
whether the machine is asleep, or whether there is a network at all.

So on a laptop, all day, every day: `lsof -i -n -P -F pcnPT` every five seconds,
plus `nettop -L 2` — which itself samples for two seconds — every other cycle.
On a busy machine `lsof -i` walks the file table of every process and is not
cheap. `CLAUDE.md` claims the app is "designed for MacBook Air users who care
about battery life" and asks contributors to keep it "under 30MB RSS". Neither
figure has ever been measured, and the polling design works against both.

Sleep and wake are unhandled too: `NSWorkspace.didWakeNotification` is not
observed, so on wake the timer fires against a machine whose network is still
coming up, and the baseline sees a burst.

**Files:** `SentryBar/ViewModels/NetworkViewModel.swift`,
`SentryBar/ViewModels/SystemViewModel.swift`,
`SentryBar/App/SentryBarApp.swift`, `SentryBar/Views/MenuBarView.swift`,
`SentryBar/Models/AppSettings.swift`.

**Done when**
- [ ] Opening the panel raises the refresh rate to the configured interval; closing it drops to a background interval of at least 60 seconds, and both view models expose the current cadence for a test to assert.
- [ ] `NSWorkspace.willSleepNotification` suspends both timers and `didWakeNotification` resumes them after a settling delay; a test asserts no refresh is issued while suspended.
- [ ] `NWPathMonitor` reports no route, and connection polling pauses until a route returns.
- [ ] Idle CPU over ten minutes with the panel closed, and RSS after one hour, are measured on a real Mac with `powermetrics` and `footprint`, and the numbers are recorded in the commit message — as measurements, dated, not as targets.

---

## Commit 12 — Stop rewriting the entire baseline on every refresh

`ConnectionBaseline.observe(_:)` ends with an unconditional `save()` (line 195).
`save()` takes `queue.sync`, encodes every entry to JSON, writes a temporary file
and calls `replaceItemAt`. With the default five-second network interval that is
a full serialise-and-replace of a file holding up to `maxEntries` = 20,000
records, twelve times a minute, forever, whether or not anything changed.

The same method is also quadratic. For each new fingerprint it evaluates
`entries.keys.filter { $0.process == fingerprint.process }.count - 1` (line 176),
a full scan of the dictionary, inside the loop over connections. A refresh that
turns up 40 new fingerprints against a 20,000-entry baseline does 800,000 key
comparisons and then rewrites the file.

`prune(now:)` runs on every call as well, filtering the entire dictionary each
time, when retention is measured in days.

**Files:** `SentryBar/Models/ConnectionBaseline.swift`,
`SentryBarTests/ConnectionBaselineTests.swift`.

**Done when**
- [ ] Saves are debounced behind a dirty flag: at most one write per configurable interval, plus a forced write on `reset`, `forget`, and app termination.
- [ ] A test observes the same unchanged connection set 50 times and asserts the file's modification date changed at most once.
- [ ] A per-process index replaces the `filter` on line 176, and a test asserts `endpointCount(forProcess:)` matches the naive count for a 5,000-entry baseline.
- [ ] `prune` runs on an interval rather than every observation, and a test still asserts entries older than `retention` are gone.
- [ ] A benchmark test observes 500 connections against a 20,000-entry baseline in under 50 ms, with the measured figure recorded.

---

## Commit 13 — Make the connection list survive a real machine

`NetworkMonitorView.body` is a `ScrollView` containing a `VStack` with a plain
`ForEach` over `groupedConnections` (line 404), and each expanded group nests
another plain `ForEach` over its connections (line 516). Nothing is lazy, so
every row is constructed on every body evaluation — which happens every five
seconds when `connections` republishes, and again for each of the other
`@Published` properties the view reads.

`groupedConnections` is a computed property that builds a `Dictionary(grouping:)`
and sorts it. It is called from `appsCard` (line 404) and again from
`summaryCard` (line 162, for `groupedConnections.count`), so the grouping and
sort run at least twice per render.

A Mac running a browser, a chat client and a sync agent routinely holds several
hundred established sockets. There is also no way to search or filter the list,
so finding the one connection an alert referred to means scrolling.

**Files:** `SentryBar/Views/NetworkMonitorView.swift`,
`SentryBar/ViewModels/NetworkViewModel.swift`.

**Done when**
- [ ] Grouping and sorting move into `NetworkViewModel` as a `@Published` value computed once per refresh; `NetworkMonitorView` reads it and never recomputes.
- [ ] The app list uses `LazyVStack` (or `List`) so off-screen rows are not built.
- [ ] The Network tab has a search field filtering by process name, address and port.
- [ ] A test feeds 800 parsed connections across 60 processes through the view model and asserts the grouped output is produced in under 20 ms.
- [ ] Scrolling with 800 connections present is checked by hand for dropped frames on a real Mac and the result recorded.

---

## Commit 14 — Tell the truth on Macs that have no battery

`BatteryService.getBatteryInfo()` starts with `var info = BatteryInfo()` and
returns it unchanged if `IOPSCopyPowerSourcesList` yields nothing — which is
exactly what happens on a Mac mini, Studio, iMac or Pro. `BatteryInfo`'s defaults
are `healthPercent: 100`, `cycleCount: 0`, `currentCharge: 100`,
`isCharging: false`.

So on every desktop Mac the System tab draws a full green health ring reading
100%, zero cycles, 100% level, and the status line "On Battery". All four are
fabricated. `SystemMonitorView.batteryCard` has no branch for absence, and
`MenuBarView.overallStatus` and `StatusIconView.statusColor` both feed
`batteryInfo.healthPercent` into the menu-bar status colour, so a value that
means "there is no battery" is being treated as a health reading.

The same `nil`-versus-default confusion is in `BatteryInfo.timeRemainingFormatted`,
which returns the string "Calculating..." for a value that on a desktop will
never be calculated.

**Files:** `SentryBar/Models/BatteryInfo.swift`,
`SentryBar/Services/BatteryService.swift`,
`SentryBar/Views/SystemMonitorView.swift`, `SentryBar/Views/MenuBarView.swift`,
`SentryBar/Views/StatusIconView.swift`, `SentryBarTests/BatteryInfoTests.swift`.

**Done when**
- [ ] `BatteryService` returns an optional or an explicit `.noBattery` case rather than a default-valued struct.
- [ ] `SystemMonitorView` hides the battery card entirely when there is no battery and says so once, rather than drawing a 100% ring.
- [ ] Neither `overallStatus` nor `statusColor` consults battery health when no battery is present; a test asserts the status is not degraded on a batteryless machine.
- [ ] A test asserts the parsing path returns the no-battery case when handed an empty power-source list.
- [ ] Verified by hand on a desktop Mac if one is available; if not, the commit message says so rather than implying it was.

---

## Commit 15 — Make notification authorization a state the user can see

`SystemViewModel.requestNotificationPermission()` is
`UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }`
— both the granted flag and the error are discarded. It is called once, from the
initialiser, and never again.

If the user denies, or has denied at some point in the past, every
`UNUserNotificationCenter.current().add(...)` in `NetworkViewModel.deliver` and
in `SystemViewModel`'s two alert methods silently does nothing. The app keeps
detecting, keeps deduplicating, keeps rate limiting, and keeps producing zero
visible output. For a tool whose entire value is the alert, "silently does
nothing" is the worst available failure mode.

`AppSettings.showNotifications` compounds this: it is a master switch that gates
the alert path *before* the log is written, so turning banners off also empties
the in-app history.

Also note that an unsigned build (see commit 18) may not be able to present
notifications at all — which needs to be established on a real Mac, not assumed
either way.

**Files:** `SentryBar/ViewModels/SystemViewModel.swift`,
`SentryBar/ViewModels/NetworkViewModel.swift`,
`SentryBar/Views/NotificationLogView.swift`,
`SentryBar/Views/SettingsView.swift`.

**Done when**
- [ ] Authorization status is queried with `getNotificationSettings` on launch and whenever the panel opens, and published.
- [ ] When status is `.denied`, the Alerts tab shows a banner saying alerts are being detected but not delivered, with a button opening `x-apple.systempreferences:com.apple.preference.notifications`.
- [ ] `showNotifications == false` suppresses banners but still writes to the in-app log; a test asserts the log grows while banners are off.
- [ ] Denying permission and then triggering an alert is exercised by hand on a real Mac, and whether the unsigned build can present notifications at all is recorded in the commit message.

---

## Commit 16 — Make the menu bar item and the panel usable without sight or colour

The whole app target contains three accessibility modifiers, all in
`NetworkMonitorView` (lines 74, 75, 96). Everything else is unlabelled.

`StatusIconView` is the worst case: it is the entire always-visible surface of
the app, and it conveys its state through a 7×7 point filled `Circle` whose only
distinguishing property is colour — red, orange or green. A colour-blind user
gets no signal, a VoiceOver user gets none either, and there is no
`accessibilityLabel` on the status item at all. `Image(systemName: appSettings.menuBarIcon)`
reads a string straight out of `UserDefaults` with no validation, so a corrupted
or downgraded value renders nothing.

The same colour-only pattern repeats in `appGroupView`'s status dot
(`NetworkMonitorView` line 445) and `MenuBarView.overallStatusBadge`.

Structurally, `MenuBarView` puts a hand-built `tabPicker` above a `TabView`
carrying `.tag()` but no `.tabItem`, which on macOS means the system also draws
its own tab strip. And the panel is pinned to `.frame(width: 360, height: 480)`
in `SentryBarApp`, so nothing reflows at larger text sizes.

**Files:** `SentryBar/Views/StatusIconView.swift`,
`SentryBar/Views/MenuBarView.swift`, `SentryBar/Views/NetworkMonitorView.swift`,
`SentryBar/Views/SystemMonitorView.swift`,
`SentryBar/Views/NotificationLogView.swift`,
`SentryBar/Views/SettingsView.swift`, `SentryBar/App/SentryBarApp.swift`.

**Done when**
- [ ] The menu-bar status is carried by a distinct SF Symbol per state as well as by colour, and the status item has an `accessibilityLabel` naming the state in words.
- [ ] `menuBarIcon` is validated against `MenuBarIconOption.allOptions` before use, falling back to the default; a test asserts an unknown stored value does not render an empty icon.
- [ ] Every button, toggle, slider and status dot across the five views has an accessibility label; the colour-only dots gain a shape or symbol distinction.
- [ ] The custom `tabPicker` and the system `TabView` strip no longer both appear.
- [ ] The panel is verified with VoiceOver, at the largest accessibility text size, and with Increase Contrast and Reduce Transparency on, on a real Mac.

---

## Commit 17 — Localise the interface and format numbers by locale

There is no localisation of any kind: no `.lproj`, no `.xcstrings`, and zero
occurrences of `NSLocalizedString`, `String(localized:)` or an explicit
`LocalizedStringKey` anywhere in the target. Every string is an English literal
in Swift.

Many are not merely unlocalised but unlocalisable as written, because they are
assembled by concatenation with hand-rolled pluralisation. `ConnectionBaseline`
lines 182–187 build `"\(known) other destination\(known == 1 ? "" : "s") over \(days) day\(days == 1 ? "" : "s")"`.
`NetworkMonitorView` line 108 does the same for "connection(s)". No language with
more than two plural forms can be expressed that way, and no translator can
reach the fragments.

`formatBytes` and `formatRate` in `ProcessRunner.swift` use
`String(format: "%.1f MB", …)`, which is fixed to a POSIX decimal point and a
hard-coded unit suffix — wrong for most of Europe, and something
`ByteCountFormatter` and `MeasurementFormatter` already do properly.

**Files:** `SentryBar/Utilities/ProcessRunner.swift` (or a new
`Utilities/Formatting.swift`), `SentryBar/Models/ConnectionBaseline.swift`,
`SentryBar/Models/MonitorAlert.swift`,
`SentryBar/Models/NetworkConnection.swift`, all files in `SentryBar/Views/`, a
new `SentryBar/Resources/Localizable.xcstrings`, `project.yml`.

**Done when**
- [ ] A `Localizable.xcstrings` catalogue exists, is referenced from `project.yml`, and every user-facing literal in `Views/` resolves through it.
- [ ] Counted strings use the catalogue's plural variants; no `? "" : "s"` remains in the source tree.
- [ ] `formatBytes` and `formatRate` are backed by `ByteCountFormatter` / `MeasurementFormatter` and honour the current locale; a test asserts a German locale produces a comma decimal separator.
- [ ] Launching with `-AppleLanguages "(de)"` shows the catalogue's German entries where present and English elsewhere, with no missing-key placeholders.

---

## Commit 18 — Decide the entitlements and sign the build honestly

`project.yml` sets `ENABLE_HARDENED_RUNTIME: true` and
`CODE_SIGN_STYLE: Automatic`, and there is no `.entitlements` file anywhere in
the repository. Every CI invocation then passes
`CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`,
including the `archive` step that produces the shipped DMG. So the hardened
runtime setting has no effect, and the published artifact carries no signature at
all.

That is not a cosmetic gap. An unsigned app has no stable code identity, which is
what `SMAppService.mainApp.register()` (commit 3) relies on, and it is plausible
that notification presentation (commit 15) is affected too. Both need to be
established on hardware rather than argued about.

There is also an unmade decision to record: SentryBar can never adopt the App
Sandbox. A sandboxed process cannot exec `/usr/sbin/lsof`, cannot read the socket
table, and cannot `kill(2)` another process. That rules out the Mac App Store
permanently, and the repository should say so and enforce it so nobody
reintroduces the flag believing it is free hardening.

To be explicit about what this commit is not: it does not pretend to notarise
anything. Notarisation needs a paid Apple Developer ID that this project does not
have. The commit adds ad-hoc signing so the hardened runtime means something
locally, adds a Developer ID path that activates only when real secrets are
present, and leaves the README's "not code-signed or notarised" section true
until that changes.

**Files:** `project.yml`, `SentryBar/Resources/SentryBar.entitlements` (new),
`.github/workflows/build.yml`, `README.md`.

**Done when**
- [ ] An explicit `SentryBar.entitlements` exists, is referenced by `CODE_SIGN_ENTITLEMENTS`, and sets `com.apple.security.app-sandbox` to `false` with a comment explaining why it can never be true.
- [ ] CI ad-hoc signs the archived app (`codesign -s - --options runtime`) and `codesign --verify --strict` passes on the artifact.
- [ ] The Developer ID path is present but gated on `secrets.MACOS_CERTIFICATE`, and is skipped — visibly, with a logged message — when the secret is absent.
- [ ] A static check fails the build if `com.apple.security.app-sandbox` is ever set to `true`.
- [ ] Whether an ad-hoc-signed build can register a login item and present a notification is tested on a real Mac and written into `README.md`.

---

## Commit 19 — Prove the release runs where the README says it runs

`README.md` and `Casks/sentrybar.rb` both promise macOS 13 Ventura or later.
`CLAUDE.md` promises "runs on both Apple Silicon and Intel". Nothing in the
repository checks either claim.

Every `xcodebuild` invocation in `.github/workflows/build.yml` — test, release
build and archive — passes `-destination 'platform=macOS,arch=arm64'`. No job
builds or runs anything for `x86_64`, and nothing inspects the shipped binary's
architectures. The DMG published to users may be arm64-only and nobody would
know.

The macOS 13 floor is unverified in a different way. API misuse would be a
compile error, so that part is safe once commit 1 lands. SF Symbols are not: a
symbol introduced after macOS 13 renders as an empty box at runtime with no
diagnostic. The tree uses several that need checking, including
`shield.checkered` (the default menu-bar icon),
`app.connected.to.app.below.fill` in `NetworkMonitorView`, and
`bolt.trianglebadge.exclamationmark.fill` in `SystemMonitorView`. CI runs only on
`macos-14`, so a macOS 13 machine has never seen this app.

**Files:** `.github/workflows/build.yml`, `project.yml`,
`SentryBar/Models/MenuBarIconOption.swift`, `SentryBar/Views/` (symbol
substitutions), `README.md`.

**Done when**
- [ ] The release job builds with `ARCHS="arm64 x86_64"` and a step asserts `lipo -archs SentryBar.app/Contents/MacOS/SentryBar` reports both.
- [ ] The test matrix includes an `x86_64` destination, or the README and cask are changed to say Apple Silicon only.
- [ ] Every `systemName:` string in the target is checked against SF Symbols availability for macOS 13, and any later-only symbol is replaced or wrapped in an availability check.
- [ ] The app is launched on a macOS 13 machine or VM; every tab is opened and no empty icon boxes appear. If no macOS 13 machine is available, the deployment target is raised to 14 and the README, cask and `install.sh` version check are all changed to match — rather than leaving an untested claim in place.

---

## Commit 20 — Make the cask and the installer verify what they ship

`Casks/sentrybar.rb` line 14 is `sha256 :no_check`, with a comment saying it is
"replaced by the release workflow with the real digest". The release job does
rewrite it — into `build/sentrybar.rb`, which is uploaded as a release asset. It
is never committed back. So the file in the repository stays `:no_check`
permanently, and anyone who installs from the tap or from a checkout gets a cask
that verifies nothing.

The CI guard next to it only compares `version` between `project.yml` and the
cask. It does not assert that `sha256` is a real digest, which is the check that
would have caught this.

`install.sh` is in better shape: it fetches `SentryBar.dmg.sha256`, refuses to
proceed without it, and compares before mounting. But the checksum comes from the
same GitHub release as the DMG, so it protects against a corrupted or truncated
transfer and not against a compromised release — and it currently reads as though
it protects against more than it does. It also runs `codesign --verify` only
after installing, to decide whether to print the Gatekeeper warning; with commit
18 landed, that check becomes meaningful and should happen before the app is
moved into place.

**Files:** `.github/workflows/build.yml`, `Casks/sentrybar.rb`, `install.sh`,
`README.md`.

**Done when**
- [ ] The release job commits the rewritten cask back to the repository (or opens a PR), so `Casks/sentrybar.rb` on the default branch carries the digest of the release it names.
- [ ] `sha256 :no_check` is absent from the repository, and a CI step fails if it reappears.
- [ ] The existing version-drift check also asserts `sha256` matches `/^[0-9a-f]{64}$/`.
- [ ] `install.sh` verifies the signature of the staged app before replacing the installed copy, and refuses on a signature that is present but invalid.
- [ ] The README's Install section states plainly that the published checksum defends against a bad download and not against a compromised release.

---

## What is deliberately not here

- **Migrating off `lsof`/`nettop` to a Network Extension.** That is the tradeoff
  the README already argues for, at length, and it is the right one for a tool
  that has to install on managed Macs.
- **Anything that is not native macOS.** The constraint stands.
- **Notarisation.** It needs a paid Developer ID. Commit 18 builds the path and
  leaves the switch off, because the alternative is a README that lies.
