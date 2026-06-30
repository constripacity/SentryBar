import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var ruleStore: ConnectionRuleStore
    @State private var showResetConfirmation = false
    @State private var showRulesManager = false

    var body: some View {
        if showRulesManager {
            RulesManagementView(ruleStore: ruleStore, isShowing: $showRulesManager)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if let update = viewModel.updateAvailable {
                        updateBanner(update)
                    }
                    generalSection
                    appearanceSection
                    notificationsSection
                    connectionRulesSection
                    batterySection
                    aboutSection
                    resetButton
                }
                .padding(16)
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("General", systemImage: "gearshape")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Toggle("Launch at Login", isOn: $viewModel.appSettings.launchAtLogin)
                .font(.caption)
                .help("Automatically start SentryBar when you log in")
                .onChange(of: viewModel.appSettings.launchAtLogin) { _ in
                    viewModel.toggleLaunchAtLogin()
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("System refresh")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(viewModel.appSettings.refreshIntervalSystem))s")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $viewModel.appSettings.refreshIntervalSystem, in: 5...30, step: 1)
                    .help("How often to check battery and thermal state (5–30 seconds)")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Network refresh")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(viewModel.appSettings.refreshIntervalNetwork))s")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $viewModel.appSettings.refreshIntervalNetwork, in: 5...30, step: 1)
                    .help("How often to scan network connections (5–30 seconds)")
            }
        }
        .padding(12)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notifications", systemImage: "bell")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Toggle("Enable Notifications", isOn: $viewModel.appSettings.showNotifications)
                .font(.caption)
                .help("Master toggle for all SentryBar notifications")

            if viewModel.appSettings.showNotifications {
                Toggle("Thermal warnings", isOn: $viewModel.appSettings.notifyOnThermalWarning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .help("Alert when your Mac is overheating")

                Toggle("Suspicious connections", isOn: $viewModel.appSettings.notifyOnSuspiciousConnection)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .help("Alert when suspicious network activity is detected")

                Toggle("Battery health drop", isOn: $viewModel.appSettings.notifyOnBatteryHealthDrop)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .help("Alert when battery health falls below threshold")

                Toggle("High bandwidth usage", isOn: $viewModel.appSettings.notifyOnHighBandwidth)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .help("Alert when a process uses excessive bandwidth in a single interval")

                Toggle("Remora verdicts", isOn: $viewModel.appSettings.notifyOnRemoraVerdict)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .help("Alert when Remora rates the wire high/critical risk")

                if viewModel.appSettings.notifyOnHighBandwidth {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Bandwidth threshold")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(viewModel.appSettings.highBandwidthThresholdMB) MB")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.appSettings.highBandwidthThresholdMB) },
                                set: { viewModel.appSettings.highBandwidthThresholdMB = Int($0) }
                            ),
                            in: 10...500,
                            step: 10
                        )
                        .help("Alert when any single process exceeds this per-interval (10–500 MB)")
                    }
                    .padding(.leading, 16)
                }
            }
        }
        .padding(12)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Connection Rules

    private var connectionRulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connection Rules", systemImage: "shield.lefthalf.filled")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Text("\(ruleStore.allowedCount) trusted, \(ruleStore.blockedCount) blocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Manage Rules...") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showRulesManager = true
                    }
                }
                .font(.caption)
                .help("Open the rules manager to add, edit, or remove connection rules")
            }
        }
        .padding(12)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Battery

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Battery", systemImage: "battery.75")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Health alert threshold")
                        .font(.caption)
                    Spacer()
                    Text("\(viewModel.appSettings.batteryHealthThreshold)%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(viewModel.appSettings.batteryHealthThreshold) },
                        set: { viewModel.appSettings.batteryHealthThreshold = Int($0) }
                    ),
                    in: 50...100,
                    step: 5
                )
                .help("Alert when battery health drops below this percentage")
            }
        }
        .padding(12)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("About", systemImage: "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Text("SentryBar")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Built with Swift + SwiftUI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Link("GitHub", destination: URL(string: "https://github.com/constripacity/SentryBar")!)
                    .font(.caption)
            }

            Toggle("Check for updates automatically", isOn: $viewModel.appSettings.checkForUpdates)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Check GitHub Releases for new versions once per day")
        }
        .padding(12)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Update Banner

    private func updateBanner(_ update: UpdateService.UpdateInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update Available: v\(update.latestVersion)")
                    .font(.caption.weight(.semibold))
                Text("You're running v\(update.currentVersion)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Link("Download", destination: URL(string: update.releaseURL)!)
                .font(.caption.weight(.medium))
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Appearance", systemImage: "paintbrush")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Menubar Icon")
                    .font(.caption)

                let icons = MenuBarIconOption.allOptions
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(icons, id: \.symbol) { option in
                        Button {
                            viewModel.appSettings.menuBarIcon = option.symbol
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: option.symbol)
                                    .font(.title3)
                                    .frame(width: 32, height: 32)
                                Text(option.label)
                                    .font(.system(size: 8))
                                    .lineLimit(1)
                            }
                            .padding(4)
                            .background(viewModel.appSettings.menuBarIcon == option.symbol ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(viewModel.appSettings.menuBarIcon == option.symbol ? Color.accentColor : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(option.label)
                    }
                }
            }
        }
        .padding(12)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button("Reset to Defaults") {
            showResetConfirmation = true
        }
        .font(.caption)
        .foregroundStyle(.red)
        .help("Reset all settings to their default values")
        .alert("Reset Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Settings Only", role: .destructive) {
                viewModel.resetToDefaults()
            }
            Button("Everything (incl. rules)", role: .destructive) {
                viewModel.resetToDefaults()
                ruleStore.clearAllRules()
            }
        } message: {
            Text("Choose what to reset. \"Settings Only\" resets preferences. \"Everything\" also clears all connection rules.")
        }
    }
}
