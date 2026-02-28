import SwiftUI
import ServiceManagement

/// ViewModel for the Settings panel
@MainActor
final class SettingsViewModel: ObservableObject {
    var appSettings = AppSettings()

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
            "com.sentrybar.highBandwidthThresholdMB"
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        // Force SwiftUI to pick up the reset values
        objectWillChange.send()
    }
}
