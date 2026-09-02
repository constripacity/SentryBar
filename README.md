<h1 align="center">SentryBar</h1>

<p align="center">
  <strong>See what your Mac is talking to — from the menu bar, without installing a system extension.</strong>
</p>

<p align="center">
  Native SwiftUI · learns what is normal for <em>your</em> machine · no telemetry, no account, no network extension
</p>

<p align="center">
  <a href="#what-it-does">What it does</a> ·
  <a href="#the-honest-tradeoff">The honest tradeoff</a> ·
  <a href="#install">Install</a> ·
  <a href="#how-the-baseline-works">How the baseline works</a> ·
  <a href="#privacy">Privacy</a>
</p>

---

> **Screenshot needed here.** The one to capture is a **notification firing** —
> "Safari reached a new destination" — not a dashboard. That is the moment the
> product exists for. Drop it at `docs/alert.png` and link it above.

## What it does

SentryBar sits in the menu bar and answers one question well:

> **Is something on this Mac connecting somewhere it never has before?**

It reads the socket table, learns which processes normally talk to which
destinations, and tells you when that changes:

```
  Safari reached a new destination
  Safari has used 63 other destinations over 12 days.
  140.82.121.0/24:443 is new.

  If this is expected, right-click the connection and trust Safari
  so it stops being reported.
```

Around that it shows the context you need to judge an alert: per-process
bandwidth, battery and thermal state, and what is using the CPU right now.

## The honest tradeoff

SentryBar reads `lsof` and `nettop`. It installs **no system extension** and
never sits in the path of your traffic.

**What that buys you.** It installs like a normal app. On a managed or corporate
Mac where a system extension will never be approved, it still works. It cannot
see, log, or interfere with the contents of your traffic, because it never
touches it.

**What it costs you, stated plainly.**

- **SentryBar cannot block a connection.** It watches and warns. Connection
  rules control what you get *told about*, not what is *allowed*.
- Polling misses connections that open and close between refreshes.
- It is slower than a kernel-level filter.

If you want blocking, use [LuLu](https://github.com/objective-see/LuLu). The two
compose well: LuLu is the gate, SentryBar is the log.

## Where it fits

| | Sees per-connection | Alerts on change | Blocks | Needs a system extension | Lives in the menu bar |
| --- | --- | --- | --- | --- | --- |
| [Stats](https://github.com/exelban/stats) | ✗ (totals only) | ✗ | ✗ | ✗ | ✓ |
| [Sniffnet](https://github.com/GyulyVGC/sniffnet) | ✓ | notifications | ✗ | packet capture | ✗ (a window) |
| [LuLu](https://github.com/objective-see/LuLu) | ✓ | per-prompt | **✓** | **✓** | ✗ |
| [bandwhich](https://github.com/imsnif/bandwhich) | ✓ | ✗ | ✗ | ✗ (needs sudo) | ✗ (a terminal) |
| **SentryBar** | ✓ | **✓ learned baseline** | ✗ | **✗** | ✓ |

Stats is a better system monitor than SentryBar will ever be, and if that is
what you want you should install Stats. SentryBar's system-health panel exists
to give an alert context — "this started when the machine began thermally
throttling" — not to compete on widgets.

## How the baseline works

The naive version of this feature flags any connection to a high port from a
process that isn't on an allowlist. On a real Mac that means WebRTC, QUIC, game
servers, every CDN and every tool you installed yourself. A monitor that cries
wolf a hundred times a day teaches you to ignore it, which is worse than not
alerting at all. (This is not hypothetical: it is what SentryBar's previous
version did.)

So SentryBar learns instead.

1. **It watches quietly for three days.** Nothing is flagged during warm-up, and
   the UI says so: *"Still learning what is normal (42%)."* Alerting from an
   empty baseline is alerting on everything.
2. **It records `(process, /24 or /48 prefix, port)`.** The subnet prefix rather
   than the exact address, because a CDN answers from a different host every
   time and exact addresses would make everything permanently new.
3. **After warm-up, a combination it has never seen is reported once**, with the
   count it is comparing against, so you can judge it.
4. **Entries expire** after 60 days, so an app you uninstalled stops shaping the
   baseline.

It is deterministic, entirely local, and you can throw it away. **Settings →
Network baseline** shows what has been learned, offers `Forget` per process for
an app that legitimately changed its endpoints, and `Reset baseline` to start
the learning period again. The file lives at
`~/Library/Application Support/SentryBar/network-baseline.json`, mode `0600`.

## Alerts that are worth reading

Every alert goes through one engine with four rules:

- **Deduplicated by key** — the same condition never notifies twice; the second
  occurrence increments a counter.
- **Repeats only every 30 minutes**, so a persistent problem reminds you
  occasionally rather than constantly.
- **Globally rate limited** — at most 6 notifications per 5 minutes, so a burst
  cannot bury the machine.
- **Snoozable** per alert or per category, with a severity floor you set.

Suppressions are written to the notification log, so if SentryBar goes quiet you
can find out *why* rather than assuming it broke.

## Install

```bash
brew install --cask sentrybar
```

or

```bash
curl -fsSL https://raw.githubusercontent.com/constripacity/SentryBar/main/install.sh | bash
```

The install script **verifies the download against the checksum published with
the release and refuses to install without one.** It stages the new copy before
removing the old, so an interrupted install never leaves you with nothing.

Requires **macOS 13 Ventura or later** (`MenuBarExtra`).

### About signing

**SentryBar is not code-signed or notarised.** Builds come from GitHub Actions
against a tagged commit and the build log is public, but there is no Apple
Developer ID behind them. Gatekeeper will refuse to open the app until you clear
the quarantine flag yourself:

```bash
xattr -dr com.apple.quarantine /Applications/SentryBar.app
```

The installer tells you this rather than doing it for you. A script that
silently disarms Gatekeeper on your behalf is exactly the pattern you should
refuse from anyone — including this one.

## Privacy

- **Nothing leaves your Mac.** No telemetry, no analytics, no accounts. The only
  outbound request in the entire codebase is an update check against the GitHub
  releases API, at most once every 24 hours, which you can turn off.
- **The baseline never leaves your Mac**, and stores subnet prefixes rather than
  full addresses.
- **No packet contents are ever read.** SentryBar reads the socket table — who is
  connected to what — and never the traffic itself. It could not read your
  traffic if it wanted to.
- **No elevated privileges.** SentryBar never asks for root, never installs a
  helper tool, and only signals processes you own.

## Ending a process

The context menu can ask a process to quit. It sends `SIGTERM`, and before it
does it:

- confirms the PID still belongs to the process you clicked on (PIDs get
  recycled, and signalling the wrong one is how a "kill" button becomes a bug
  report);
- confirms you own it — SentryBar never signals a root-owned process and never
  asks for privileges to do so;
- refuses for known macOS system services.

If it refuses, it tells you which of those it was.

## Building

```bash
brew install xcodegen
xcodegen generate
open SentryBar.xcodeproj
```

Tests: `xcodebuild test -scheme SentryBar -destination 'platform=macOS'`.
CI runs them on every push — which it did not do before, despite the tests
existing.

> **This release has not been compiled.** The v0.8.0 work was done on a machine
> with no Swift toolchain and no macOS, so no source file here has been built
> and none of the 142 test functions has been executed. What was checked
> statically: every Swift file's brackets balance and no shell is invoked
> outside `ProcessRunner` (`python3 scripts/swift_static_checks.py`, which CI
> also runs). Expect to fix compile errors on the first real build; that is
> commit 1 of [`docs/NEXT_20_COMMITS.md`](docs/NEXT_20_COMMITS.md).

Architecture: SwiftUI + `MenuBarExtra`, MVVM, no third-party dependencies. Every
external tool is invoked through `ProcessRunner` with an argv vector and **no
shell**; CI fails the build if a `Process()` appears anywhere else.

## What SentryBar is not

- **Not a firewall.** It cannot block anything. See
  [the tradeoff](#the-honest-tradeoff).
- **Not malware detection.** "New destination" means new, not malicious. Most new
  destinations are an app updating itself.
- **Not a full system monitor.** [Stats](https://github.com/exelban/stats) is
  better at that and you should use it if that is what you want.

## License

MIT — see [LICENSE](LICENSE).
