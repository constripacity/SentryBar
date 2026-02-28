# SentryBar

## Project Overview
SentryBar is a lightweight macOS menubar app that combines system health monitoring with network security monitoring. It targets MacBook Air users who care about battery life, thermal performance, and knowing what their apps are doing on the network.

**Stack:** Swift 5.9 + SwiftUI (native macOS, no Electron/web)
**Target:** macOS 13.0+ (Ventura) — runs on both Apple Silicon and Intel
**Architecture:** MVVM (Model-View-ViewModel)
**Distribution:** GitHub Releases as .dmg, eventually Homebrew
**Repository:** https://github.com/constripacity/SentryBar
**Version:** 0.5.0

---

## Architecture & Code Organization

```
SentryBar/
├── App/           → App entry point, lifecycle (@main struct)
├── Models/        → Plain data structs (BatteryInfo, ThermalInfo, NetworkConnection, AppSettings, ConnectionRule, BandwidthInfo)
├── Services/      → System interaction layer (IOKit, ProcessInfo, shell commands)
├── ViewModels/    → @MainActor ObservableObject classes managing state + timers
├── Views/         → SwiftUI views (menubar panel, tabs, cards, sparkline)
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
- **Suspicious Detection** → heuristic: known bad ports (4444, 5555, 6666, 1337, 31337, 8888) + unknown processes on ephemeral ports
- **Process Kill** → `kill <pid>` via shell (PID validated, root-owned blocked, system processes blocked, requires confirmation)
- **Connection Rules** → allow/block list per process name, remote address, or port (JSON persistence, 0600 permissions)
- **Bandwidth Tracking** → per-process bandwidth via `nettop`, top consumers card, high-bandwidth alerts
- **Rate Calculation** → KB/s rates via wall-clock timing of nettop, sparkline visualization (last 10 snapshots)
- **Stats** → connection count, suspicious count, upload/download rates

### Settings (implemented)
- Launch at login (via SMAppService)
- Configurable refresh intervals (system: 5-30s, network: 5-30s)
- Notification toggles (thermal, suspicious, battery health, high bandwidth)
- Battery health threshold setting
- High bandwidth threshold (MB)
- Reset to defaults
- Dynamic version display from app bundle

### Not Yet Implemented
- [ ] Notification history / log view
- [ ] Homebrew formula
- [ ] Sparkle or built-in update mechanism

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

# Run tests (104 unit tests)
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
- `.github/workflows/build.yml` runs on push/PR to main
- Installs xcodegen, generates project, builds Release
- On tags: archives, creates DMG, uploads as artifact

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

### Current Coverage (104 tests, all passing)
| Test Suite | Tests | Coverage Area |
|---|---|---|
| BatteryInfoTests | 6 | Model defaults, time formatting |
| ThermalInfoTests | 5 | State descriptions, recommendations |
| NetworkConnectionTests | 17 | Suspicion heuristics, classification overrides, known processes |
| ConnectionRuleTests | 12 | Rule CRUD, matching by process/address/port, first-rule-wins |
| NetworkServiceTests | 28 | lsof parsing (IPv6, escaped names, state extraction), ps parsing, connection string parsing, unescapeLsof |
| BandwidthServiceTests | 18 | nettop parsing, process field parsing, aggregation, snapshots, rate calculation |
| UtilitiesTests | 18 | formatBytes, formatRate, Date extension, Optional extension |

### Strategy
- Unit test Services independently (mock shell output for NetworkService)
- Test ViewModel state transitions (e.g., suspicious count updates after refresh)
- Test model logic (NetworkConnection.evaluateSuspicion, BatteryInfo.timeRemainingFormatted)
- IPv6 test data uses RFC 3849 documentation addresses (2001:db8::)
- No UI tests needed yet — focus on service/logic coverage first

## Git Workflow
- **Author identity:** constripacity <constripacity@users.noreply.github.com>
- Branch naming: `feature/description`, `fix/description`, `refactor/description`
- Commit messages: imperative mood, e.g., "Add settings panel with launch-at-login toggle"
- Tag releases as `v0.1.0`, `v0.2.0`, etc. (tags trigger CI/CD DMG builds)
- `.xcodeproj` is gitignored — regenerate with `xcodegen generate`
- Strip EXIF/C2PA metadata from image assets before committing

---

## Known Issues & Technical Debt
1. **No notification rate limiting** — rapid suspicious connection churn could flood notifications
2. **System process allowlist is incomplete** — `killProcess()` uses root-owner check as defense-in-depth, but `NetworkConnection.systemProcesses` set could be expanded
