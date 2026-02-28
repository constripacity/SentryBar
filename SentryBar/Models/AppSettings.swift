import SwiftUI

/// Persistent app settings backed by UserDefaults via @AppStorage
final class AppSettings: ObservableObject {
    @AppStorage("com.sentrybar.launchAtLogin")
    var launchAtLogin: Bool = false

    @AppStorage("com.sentrybar.refreshIntervalSystem")
    var refreshIntervalSystem: Double = 10.0

    @AppStorage("com.sentrybar.refreshIntervalNetwork")
    var refreshIntervalNetwork: Double = 5.0

    @AppStorage("com.sentrybar.showNotifications")
    var showNotifications: Bool = true

    @AppStorage("com.sentrybar.notifyOnThermalWarning")
    var notifyOnThermalWarning: Bool = true

    @AppStorage("com.sentrybar.notifyOnSuspiciousConnection")
    var notifyOnSuspiciousConnection: Bool = true

    @AppStorage("com.sentrybar.notifyOnBatteryHealthDrop")
    var notifyOnBatteryHealthDrop: Bool = true

    @AppStorage("com.sentrybar.batteryHealthThreshold")
    var batteryHealthThreshold: Int = 80

    @AppStorage("com.sentrybar.notifyOnHighBandwidth")
    var notifyOnHighBandwidth: Bool = false

    @AppStorage("com.sentrybar.highBandwidthThresholdMB")
    var highBandwidthThresholdMB: Int = 50
}
