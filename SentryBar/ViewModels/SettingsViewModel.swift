import SwiftUI
import ServiceManagement

/// ViewModel for the Settings panel
@MainActor
final class SettingsViewModel: ObservableObject {
    var appSettings = AppSettings()
    @Published var updateAvailable: UpdateService.UpdateInfo?

    private let updateService = UpdateService()

    func checkForUpdates() {
        guard appSettings.checkForUpdates else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            let info = await self.updateService.checkForUpdate()
            await MainActor.run {
                self.updateAvailable = info
            }
        }
    }

    func toggleLaunchAtLogin() {
        do {
            if appSettings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert toggle on failure
            appSettings.launchAtLogin.toggle()
        }
    }

    func resetToDefaults() {
        let defaults = UserDefaults.standard
        let keys = [
            "com.sentrybar.launchAtLogin",
            "com.sentrybar.refreshIntervalSystem",
            "com.sentrybar.refreshIntervalNetwork",
            "com.sentrybar.showNotifications",
            "com.sentrybar.notifyOnThermalWarning",
            "com.sentrybar.notifyOnSuspiciousConnection",
            "com.sentrybar.notifyOnBatteryHealthDrop",
            "com.sentrybar.batteryHealthThreshold",
            "com.sentrybar.notifyOnHighBandwidth",
            "com.sentrybar.highBandwidthThresholdMB",
            "com.sentrybar.checkForUpdates",
            "com.sentrybar.menuBarIcon"
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        // Force SwiftUI to pick up the reset values
        objectWillChange.send()
    }
}
