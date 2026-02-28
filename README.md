# SentryBar

A lightweight macOS menubar app that monitors your system health and network activity in real-time.

Built natively with **Swift & SwiftUI** for minimal resource usage — perfect for MacBook Air users.

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

### System Monitor
- Battery health percentage & cycle count
- Thermal state indicator (Nominal / Fair / Serious / Critical)
- Top CPU-consuming processes
- Smart alerts for thermal throttling & battery degradation

### Network Monitor
- Live view of apps making outbound connections
- Per-app bandwidth rate tracking with sparkline charts (KB/s)
- Top bandwidth consumers card
- Suspicious connection detection (known bad ports + unknown process heuristics)
- Connection allow/block rules (per process, address, or port)
- One-click process termination with confirmation
- High bandwidth usage alerts

### Settings
- Launch at login toggle
- Configurable refresh intervals (system & network)
- Notification preferences (thermal, suspicious, battery, bandwidth)
- Battery health & bandwidth alert thresholds

### UX
- Lives in the menubar — zero dock clutter
- Tabbed dropdown panel (System / Network / Settings)
- Color-coded status indicators
- Native macOS notifications for alerts

---

## Install

### One-line install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/constripacity/SentryBar/main/install.sh | bash
```

This downloads the latest `.dmg` from GitHub Releases, installs `SentryBar.app` to `/Applications`, and cleans up automatically.

### Download manually

1. Go to [**Releases**](https://github.com/constripacity/SentryBar/releases/latest)
2. Download `SentryBar.dmg`
3. Open the DMG and drag `SentryBar.app` to your Applications folder
4. Launch SentryBar — it appears in your menubar

### Build from source

Requires macOS 13.0+, Xcode 15.0+, and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/constripacity/SentryBar.git
cd SentryBar
xcodegen generate
xcodebuild build -project SentryBar.xcodeproj -scheme SentryBar -configuration Release
```

Or open in Xcode:

```bash
open SentryBar.xcodeproj   # Cmd+R to run
```

## Project Structure

```
SentryBar/
├── SentryBar/
│   ├── App/                  # App entry point & lifecycle
│   │   └── SentryBarApp.swift
│   ├── Models/               # Data models
│   │   ├── AppSettings.swift
│   │   ├── BandwidthInfo.swift
│   │   ├── BatteryInfo.swift
│   │   ├── ConnectionRule.swift
│   │   ├── NetworkConnection.swift
│   │   ├── NotificationLog.swift
│   │   └── ThermalInfo.swift
│   ├── Services/             # System & network data providers
│   │   ├── BandwidthService.swift
│   │   ├── BatteryService.swift
│   │   ├── NetworkService.swift
│   │   └── ThermalService.swift
│   ├── ViewModels/           # Observable state managers
│   │   ├── NetworkViewModel.swift
│   │   ├── SettingsViewModel.swift
│   │   └── SystemViewModel.swift
│   ├── Views/                # SwiftUI views
│   │   ├── MenuBarView.swift
│   │   ├── NetworkMonitorView.swift
│   │   ├── NotificationLogView.swift
│   │   ├── RulesManagementView.swift
│   │   ├── SettingsView.swift
│   │   ├── SparklineView.swift
│   │   ├── StatusIconView.swift
│   │   └── SystemMonitorView.swift
│   ├── Utilities/            # Helpers & extensions
│   │   ├── Extensions.swift
│   │   └── ShellHelper.swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
├── SentryBarTests/           # 127 unit tests
├── install.sh                # One-click installer
├── project.yml               # xcodegen spec
├── .gitignore
├── LICENSE
├── CLAUDE.md
└── README.md
```

## Security

SentryBar runs **unsandboxed** because it needs access to system tools (`lsof`, `ps`, `nettop`, `kill`) for network and process monitoring. Security measures include:

- Shell commands use only hardcoded templates with numeric-only interpolation (no string injection possible)
- PID validation rejects system-critical processes (PID 0, 1) and root-owned processes before kill
- Connection rules stored with restrictive file permissions (0600)
- stderr is discarded from shell output to prevent information leakage
- Hardened Runtime is enabled for distribution builds

## Roadmap

- [x] Menubar shell with tabbed UI
- [x] Battery health monitoring (IOKit)
- [x] Thermal state tracking
- [x] Process CPU ranking
- [x] Network connection monitoring (lsof)
- [x] Suspicious connection detection
- [x] Process kill with confirmation
- [x] UNUserNotificationCenter alerts
- [x] Settings panel (launch at login, intervals, notifications)
- [x] Connection allow/block rules (JSON persistence)
- [x] Bandwidth tracking (nettop)
- [x] Rate calculation (KB/s) & sparkline visualization
- [x] App icon
- [x] Unit tests (127 tests)
- [x] Notification history / log view
- [x] One-click install (GitHub Releases + install script)
- [ ] Homebrew cask formula
- [ ] Auto-update mechanism

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI + MenuBarExtra |
| Battery | IOKit (AppleSmartBattery) |
| Thermal | ProcessInfo.thermalState |
| Network | lsof, nettop (via Shell.run) |
| Settings | @AppStorage (UserDefaults) |
| Rules | JSON (Codable) |
| Notifications | UNUserNotificationCenter |
| Build | xcodegen + xcodebuild |
| Architecture | MVVM |

## Contributing

Contributions welcome! Please open an issue first to discuss proposed changes.

## License

MIT License — see [LICENSE](LICENSE) for details.
