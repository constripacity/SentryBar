# SentryBar

## Project Overview
SentryBar is a lightweight macOS menubar app that combines system health monitoring with network security monitoring. It targets MacBook Air users who care about battery life, thermal performance, and knowing what their apps are doing on the network.

**Stack:** Swift 5.9 + SwiftUI (native macOS, no Electron/web)
**Target:** macOS 13.0+ (Ventura) — runs on both Apple Silicon and Intel
**Architecture:** MVVM (Model-View-ViewModel)
**Distribution:** GitHub Releases as .dmg, one-click install script, Homebrew cask
**Repository:** https://github.com/constripacity/SentryBar
**Version:** 0.7.0

---

## Architecture & Code Organization

```
SentryBar/
├── App/           → App entry point, lifecycle (@main struct)
├── Models/        → Plain data structs (BatteryInfo, ThermalInfo, NetworkConnection, AppSettings, ConnectionRule, BandwidthInfo, NotificationLog, MenuBarIconOption)
├── Services/      → System interaction layer (IOKit, ProcessInfo, shell commands)
├── ViewModels/    → @MainActor ObservableObject classes managing state + timers
├── Views/         → SwiftUI views (menubar panel, tabs, cards, sparkline, notification log)
├── Utilities/     → Extensions and helpers (Shell.run, formatBytes, formatRate)
└── Resources/     → Info.plist, Assets.xcassets (app icon)
```

### Data Flow
```
System APIs (IOKit, ProcessInfo, lsof, nettop)
  → Services (BatteryService, ThermalService, NetworkService, BandwidthService)
    → ViewModels (SystemViewModel, NetworkViewModel, SettingsViewModel) [@Published properties]
      → Views (SwiftUI, auto-update via @ObservedObject)
```

### Key Patterns
- **MenuBarExtra** with `.window` style creates the dropdown panel (not a traditional menu)
- **LSUIElement = YES** in Info.plist hides the app from the Dock
- ViewModels own Timer instances for polling (battery: 10s, network: 5s)
- ThermalService uses NotificationCenter for event-driven thermal state changes
- NetworkService shells out to `lsof` and `ps` via `Shell.run()` in Utilities/ShellHelper.swift
- BandwidthService shells out to `nettop` via `Shell.run()` with 15s timeout; wall-clock duration measured for rate calculation
- All UI updates happen on @MainActor; heavy work uses Task.detached
- Connection rules stored as JSON at ~/Library/Application Support/SentryBar/rules.json (0600 permissions)
- Settings persisted via `@AppStorage("com.sentrybar.*")` keys
- Version display reads dynamically from `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`
- Info.plist uses `$(MARKETING_VERSION)` build variable from project.yml

---

## Coding Standards

### Swift Style
- Use Swift's modern concurrency (async/await, Task, @MainActor) — NOT completion handlers
- Prefer `let` over `var` unless mutation is required
- Use `guard` for early returns instead of nested `if let`
- Keep functions under 40 lines; extract helpers when they grow
- Use `// MARK: -` comments to organize view sections
- Naming: camelCase for properties/functions, PascalCase for types
- Access control: mark classes `final` unless inheritance is needed; use `private` by default

### SwiftUI Conventions
- Views should be thin — no business logic, only layout and binding
- Extract subviews as computed properties (e.g., `private var batteryCard: some View`)
- Use `.background(.ultraThinMaterial)` or `.background(.background.opacity(0.6))` for cards
- Color-code status: green = healthy, orange = warning, red = critical
- Cards use `RoundedRectangle(cornerRadius: 10)` with subtle stroke borders
- All interactive elements need `.help()` tooltips for accessibility

### ViewModel Rules
- Always annotate with `@MainActor`
- Use `@Published` for all UI-bound state
- Create/invalidate timers in `startMonitoring()` / `stopMonitoring()`
- Set state flags synchronously on MainActor before launching Task.detached (e.g., `isMeasuringBandwidth`)
- Background work pattern:
  ```swift
  Task.detached { [weak self] in
      guard let self else { return }
      let result = await self.someService.doWork()
      await MainActor.run {
          self.someProperty = result
      }
  }
  ```

### Service Rules
- Services are plain classes (no ObservableObject, no SwiftUI imports)
- Services handle all system interaction (IOKit, shell commands, Process())
- Shell commands go through `Shell.run()` in Utilities/ShellHelper.swift (5s default timeout, 15s for nettop)
- Always handle errors gracefully — return sensible defaults, never crash

### Security Rules
- **Never interpolate user-supplied strings into Shell.run() commands** — only Int/Int32 types are safe
- Shell.run() sends stderr to `FileHandle.nullDevice` to prevent info leakage
- Shell.run() reads pipe data concurrently to prevent pipe buffer deadlock
- `killProcess()` must validate PID > 1 and check process owner is not root
- Rules file must be saved with POSIX 0600 permissions
- No force-unwraps on system API results (use guard/fallback)

---

## Feature Modules

### System Monitor (implemented)
- **BatteryService** → reads IOKit (AppleSmartBattery) for health%, cycle count, charge level, charging status
- **ThermalService** → reads ProcessInfo.processInfo.thermalState, listens for thermalStateDidChangeNotification
- **Top Processes** → parsed from `ps -Ao pid,comm,%cpu -r`
- **Alerts** → UNUserNotificationCenter for thermal warnings, battery health drops

### Network Monitor (implemented)
- **Connections** → parsed from `lsof -i -n -P` (ESTABLISHED connections)
- **lsof Parsing** → handles escaped process names (`\xHH`), IPv6 bracket stripping, actual state extraction, robust field indexing
- **Suspicious Detection** → heuristic: known bad ports (4444, 5555, 6666, 1337, 31337, 8888) + unknown processes on ephemeral ports; 50+ system processes and 60+ known apps whitelisted to reduce false positives
- **Process Kill** → `kill <pid>` via shell (PID validated, root-owned blocked, system processes blocked, requires confirmation)
- **Connection Rules** → allow/block list per process name, remote address, or port (JSON persistence, 0600 permissions)
- **Bandwidth Tracking** → per-process bandwidth via `nettop`, top consumers card, high-bandwidth alerts
- **Rate Calculation** → KB/s rates via wall-clock timing of nettop, sparkline visualization (last 10 snapshots)
- **Session Data Usage** → cumulative upload/download totals since app launch, per-app breakdown with bar chart
- **Grouped App View** → connections grouped by process name, expand/collapse, inline Trust/Block buttons, friendly port labels (e.g., 443 → "Secure web (HTTPS)")
- **Stats** → connection count, suspicious count, upload/download rates, active apps count

### Notification Log (implemented)
- **NotificationLog** → @MainActor ObservableObject with ring buffer (max 50 entries, newest-first)
- **NotificationType** → thermal, battery, suspicious, bandwidth — each with icon and label
- **Alerts Tab** → shows past notifications with type badges, timestamps, clear all button
- **Integration** → SystemViewModel and NetworkViewModel log alerts to shared NotificationLog

### Settings (implemented)
- Launch at login (via SMAppService)
- Configurable refresh intervals (system: 5-30s, network: 5-30s)
- Notification toggles (thermal, suspicious, battery health, high bandwidth)
- Battery health threshold setting
- High bandwidth threshold (MB)
- Menubar icon customization (10 SF Symbol choices)
- Auto-update toggle (checks GitHub Releases once per 24h)
- Reset to defaults
- Dynamic version display from app bundle

### Homebrew Cask (implemented)
- **Cask formula** at `Casks/sentrybar.rb` — ready for a separate `homebrew-sentrybar` tap repo
- Install: `brew tap constripacity/sentrybar && brew install sentrybar`
- Livecheck auto-detects new GitHub Releases via tag regex

### Auto-Update Checker (implemented)
- **UpdateService** → lightweight GitHub Releases API check (no Sparkle, no heavyweight frameworks)
- Checks at most once per 24 hours (battery-friendly, cooldown via UserDefaults timestamp)
- Shows blue banner in Settings when update available, with direct download link
- Toggle in Settings: "Check for updates automatically"

### Menubar Icon Customization (implemented)
- **MenuBarIconOption** model → 10 SF Symbol choices (shields, network, eye, cpu, antenna, etc.)
- Icon picker grid in Settings → Appearance section
- Persisted via `@AppStorage("com.sentrybar.menuBarIcon")`
- StatusIconView reads the setting dynamically

### Notification Rate Limiting (implemented)
- 60-second cooldown per notification type (suspicious, bandwidth, thermal, battery)
- Prevents flooding during rapid state churn (e.g., flapping suspicious connections)
- Cooldown tracked via `lastXAlertTime: Date?` in each ViewModel

---

## Build & Run

### Prerequisites
- Xcode 15.0+ (or command line tools)
- xcodegen (`brew install xcodegen`) — generates .xcodeproj from project.yml

### Generating the Xcode Project
```bash
cd SentryBar
xcodegen generate   # Creates SentryBar.xcodeproj from project.yml
```

### Xcode
```bash
# Open in Xcode
open SentryBar.xcodeproj

# Build from command line
xcodebuild build \
  -project SentryBar.xcodeproj \
  -scheme SentryBar \
  -configuration Debug

# Run tests (142 test functions; see the inventory below —
# none of them have ever been executed)
xcodebuild test \
  -project SentryBar.xcodeproj \
  -scheme SentryBar
```

### Creating a Release DMG
```bash
xcodebuild archive \
  -scheme SentryBar \
  -configuration Release \
  -archivePath build/SentryBar.xcarchive

hdiutil create -volname "SentryBar" \
  -srcfolder build/SentryBar.xcarchive/Products/Applications/SentryBar.app \
  -ov -format UDZO build/SentryBar.dmg
```

### CI/CD
- `.github/workflows/build.yml` runs on push/PR to main and on `v*` tags
- Installs xcodegen, generates project, builds Release
- On tags: archives, creates DMG, creates GitHub Release with DMG attached (via `softprops/action-gh-release@v2`)

### One-Click Install
```bash
curl -fsSL https://raw.githubusercontent.com/constripacity/SentryBar/main/install.sh | bash
```
- `install.sh` downloads latest DMG from GitHub Releases, mounts, copies to `/Applications`, cleans up
- Manual: download `SentryBar.dmg` from [Releases](https://github.com/constripacity/SentryBar/releases/latest)

### Homebrew
```bash
brew tap constripacity/sentrybar
brew install sentrybar
```
- Cask formula at `Casks/sentrybar.rb` — copy to a `homebrew-sentrybar` tap repo for distribution
- Livecheck auto-detects new releases; update sha256 on each release

---

## Important: Do NOT Modify
- `Info.plist` → `LSUIElement = YES` (removing this makes a dock icon appear)
- The MVVM folder structure (App/, Models/, Services/, ViewModels/, Views/)
- `MenuBarExtra` with `.menuBarExtraStyle(.window)` in SentryBarApp.swift
- The `@main` attribute on SentryBarApp
- `project.yml` → `GENERATE_INFOPLIST_FILE: false` (preserves custom Info.plist)

## Important: Keep Lightweight
- SentryBar is designed for MacBook Air users who care about battery life
- Timer intervals should not go below 5 seconds
- Avoid continuous polling — prefer event-driven updates where possible (like thermalStateDidChangeNotification)
- Never import heavyweight frameworks (WebKit, AVFoundation, etc.)
- Shell commands must have timeouts — don't let `lsof` hang the app
- Profile memory usage: the app should stay under 30MB RSS

---

## Testing

### Test inventory (142 test functions — NONE have been executed)

**These tests have never run.** The v0.8.0 revival was done on Linux with no
Swift toolchain, no Xcode and no macOS, so nothing in this repository has been
compiled since v0.6.0. The previous version of this section read "136 tests,
all passing"; the count was real, the "all passing" was not supported by
anything — CI at that point ran `xcodebuild build` and never `xcodebuild test`.
Do not repeat that claim until a run on a Mac produces it.

Counted with `grep -c "func test" SentryBarTests/*.swift`:

| Test suite | Test functions |
|---|---|
| ConnectionBaselineTests | 22 |
| BandwidthServiceTests | 18 |
| UtilitiesTests | 18 |
| NetworkServiceTests | 16 |
| AlertEngineTests | 15 |
| ConnectionRuleTests | 12 |
| NotificationLogTests | 11 |
| NetworkConnectionTests | 10 |
| BatteryInfoTests | 6 |
| ThermalInfoTests | 5 |
| UpdateServiceTests | 5 |
| MenuBarIconOptionTests | 4 |
| **Total** | **142** |

What the newer suites cover: `ConnectionBaselineTests` — fingerprint
generalisation to /24 and /48, the warm-up period, retention and the entry cap,
persistence and file permissions, and what Settings lists.
`AlertEngineTests` — deduplication, the repeat window, the rate limit, snoozes
and the severity floor. `NetworkServiceTests` — `lsof -F` field parsing and
process termination outcomes.

### Strategy
- Unit test Services independently (feed ProcessRunner output in as fixtures)
- Test ViewModel state transitions (e.g., suspicious count updates after refresh)
- Test model logic (ConnectionBaseline, AlertEngine, BatteryInfo.timeRemainingFormatted).
  `NetworkConnection.evaluateSuspicion` is deprecated and always returns false: the
  allowlist-and-high-port heuristic it implemented was replaced by the learned baseline.
- IPv6 test data uses RFC 3849 documentation addresses (2001:db8::)
- No UI tests yet. The first job on a Mac is to make the existing suite run at all —
  see docs/NEXT_20_COMMITS.md, commit 1.

## Git Workflow
- **Author identity:** constripacity <constripacity@users.noreply.github.com>
- Branch naming: `feature/description`, `fix/description`, `refactor/description`
- Commit messages: imperative mood, e.g., "Add settings panel with launch-at-login toggle"
- Tag releases as `v0.1.0`, `v0.2.0`, etc. (tags trigger CI/CD DMG builds)
- `.xcodeproj` is gitignored — regenerate with `xcodegen generate`
- Strip EXIF/C2PA metadata from image assets before committing

---

## Known Issues & Technical Debt
1. ~~**No notification rate limiting**~~ — resolved in v0.7.0: 60-second cooldown per notification type

## Releases
- **v0.7.0** — Homebrew cask, auto-update checker, menubar icon customization, notification rate limiting
- **v0.6.0** — one-click install (install.sh + GitHub Releases automation), notification log, network UX redesign, session data tracker, expanded known processes, battery health fix
- **v0.5.0** — rate calculation (KB/s) with sparkline, lsof hardening, security hardening, app icon, open-source release
- CI uses Xcode 16.2 on `macos-14` runner (project format 77 requires Xcode 16+)
- Tags trigger automated GitHub Releases with DMG attached
