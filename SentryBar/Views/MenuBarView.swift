import SwiftUI

enum SentryTab: String, CaseIterable {
    case system = "System"
    case network = "Network"
    case notifications = "Alerts"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .system: return "cpu"
        case .network: return "network"
        case .notifications: return "bell"
        case .settings: return "gearshape"
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var systemVM: SystemViewModel
    @ObservedObject var networkVM: NetworkViewModel
    @ObservedObject var settingsVM: SettingsViewModel
    @ObservedObject var ruleStore: ConnectionRuleStore
    @ObservedObject var notificationLog: NotificationLog
    @State private var selectedTab: SentryTab = .system

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Tab picker
            tabPicker

            // Content
            TabView(selection: $selectedTab) {
                SystemMonitorView(viewModel: systemVM)
                    .tag(SentryTab.system)

                NetworkMonitorView(viewModel: networkVM)
                    .tag(SentryTab.network)

                NotificationLogView(notificationLog: notificationLog)
                    .tag(SentryTab.notifications)

                SettingsView(viewModel: settingsVM, ruleStore: ruleStore)
                    .tag(SentryTab.settings)
            }
            .tabViewStyle(.automatic)

            Divider()

            // Footer
            footerView
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "shield.checkered")
                .font(.title2)
                .foregroundStyle(.blue)

            Text("SentryBar")
                .font(.headline)

            Spacer()

            overallStatusBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var overallStatusBadge: some View {
        let status = overallStatus
        return HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.15))
        .clipShape(Capsule())
    }

    private var overallStatus: (color: Color, label: String) {
        let thermalState = systemVM.thermalInfo.state
        let batteryHealth = systemVM.batteryInfo.healthPercent

        if thermalState == .critical || batteryHealth < 50 || networkVM.suspiciousCount > 0 {
            return (.red, "Critical")
        } else if thermalState == .serious || thermalState == .fair || batteryHealth < 80 {
            return (.orange, "Warning")
        }
        return (.green, "Healthy")
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 2) {
            ForEach(SentryTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.caption)
                        Text(tab.rawValue)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button("Settings") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .settings
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quit SentryBar") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
