# SentryBar

## Project Overview
SentryBar is a lightweight macOS menubar app that combines system health monitoring with network security monitoring. It targets MacBook Air users who care about battery life, thermal performance, and knowing what their apps are doing on the network.

**Stack:** Swift 5.9 + SwiftUI (native macOS, no Electron/web)
**Target:** macOS 13.0+ (Ventura) — runs on both Apple Silicon and Intel
**Architecture:** MVVM (Model-View-ViewModel)
**Distribution:** GitHub Releases as .dmg, eventually Homebrew
**Version:** 0.4.0

---

## Architecture & Code Organization

```
SentryBar/
├── App/           → App entry point, lifecycle (@main struct)
├── Models/        → Plain data structs (BatteryInfo, ThermalInfo, NetworkConnection, AppSettings, ConnectionRule, BandwidthInfo)
├── Services/      → System interaction layer (IOKit, ProcessInfo, shell commands)
├── ViewModels/    → @MainActor ObservableObject classes managing state + timers
├── Views/         → SwiftUI views (menubar panel, tabs, cards)
├── Utilities/     → Extensions and helpers (Shell.run, formatBytes)
└── Resources/     → Info.plist, assets
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
- BandwidthService shells out to `nettop` via `Shell.run()` with 15s timeout
- All UI updates happen on @MainActor; heavy work uses Task.detached
- Connection rules stored as JSON at ~/Library/Application Support/SentryBar/rules.json
- Settings persisted via `@AppStorage("com.sentrybar.*")` keys

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

---

## Feature Modules

### System Monitor (implemented)
- **BatteryService** → reads IOKit (AppleSmartBattery) for health%, cycle count, charge level, charging status
- **ThermalService** → reads ProcessInfo.processInfo.thermalState, listens for thermalStateDidChangeNotification
- **Top Processes** → parsed from `ps -Ao pid,comm,%cpu -r`
- **Alerts** → UNUserNotificationCenter for thermal warnings, battery health drops

### Network Monitor (implemented)
- **Connections** → parsed from `lsof -i -n -P` (ESTABLISHED connections)
- **Suspicious Detection** → heuristic: known bad ports (4444, 5555, 6666, 1337, 31337, 8888) + unknown processes on ephemeral ports
- **Process Kill** → `kill <pid>` via shell (blocked for system processes, requires confirmation)
- **Connection Rules** → allow/block list per process name, remote address, or port (JSON persistence)
- **Bandwidth Tracking** → per-process bandwidth via `nettop`, top consumers card, high-bandwidth alerts
- **Stats** → connection count, suspicious count, upload/download totals

### Settings (implemented)
- Launch at login (via SMAppService)
- Configurable refresh intervals (system: 5-30s, network: 5-30s)
- Notification toggles (thermal, suspicious, battery health, high bandwidth)
- Battery health threshold setting
- High bandwidth threshold (MB)
- Reset to defaults

### Not Yet Implemented
- [ ] Notification history / log view
- [ ] Homebrew formula
- [ ] App icon / SF Symbol customization
- [ ] Sparkle or built-in update mechanism
- [ ] Rate calculation (KB/s) and sparkline visualization

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

# Run tests (80 unit tests)
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

### Current Coverage (80 tests, all passing)
| Test Suite | Tests | Coverage Area |
|---|---|---|
| BatteryInfoTests | 6 | Model defaults, time formatting |
| ThermalInfoTests | 5 | State descriptions, recommendations |
| NetworkConnectionTests | 17 | Suspicion heuristics, classification overrides, known processes |
| ConnectionRuleTests | 12 | Rule CRUD, matching by process/address/port, first-rule-wins |
| NetworkServiceTests | 14 | lsof parsing, ps parsing, connection string parsing |
| BandwidthServiceTests | 14 | nettop parsing, process field parsing, aggregation, snapshots |
| UtilitiesTests | 12 | formatBytes, Date extension, Optional extension |

### Strategy
- Unit test Services independently (mock shell output for NetworkService)
- Test ViewModel state transitions (e.g., suspicious count updates after refresh)
- Test model logic (NetworkConnection.evaluateSuspicion, BatteryInfo.timeRemainingFormatted)
- No UI tests needed yet — focus on service/logic coverage first

## Git Workflow
- Branch naming: `feature/description`, `fix/description`, `refactor/description`
- Commit messages: imperative mood, e.g., "Add settings panel with launch-at-login toggle"
- Tag releases as `v0.1.0`, `v0.2.0`, etc. (tags trigger CI/CD DMG builds)

---

## Known Issues & Technical Debt
1. **lsof parsing is fragile** — output format can vary; needs more robust parsing with edge case handling
2. **No rate calculation** — bandwidth shows total bytes per interval, not KB/s rate over time
