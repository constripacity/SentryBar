import SwiftUI
import Combine
import UserNotifications

/// ViewModel for system monitoring (battery, thermal, processes)
@MainActor
final class SystemViewModel: ObservableObject {
    @Published var batteryInfo = BatteryInfo()
    @Published var thermalInfo = ThermalInfo()
    @Published var topProcesses: [AppProcess] = []

    private let batteryService = BatteryService()
    private let thermalService = ThermalService()
    private let networkService = NetworkService() // Also provides process data
    private let appSettings: AppSettings
    private var refreshTimer: Timer?
    private var currentInterval: Double = 0

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        requestNotificationPermission()
        startMonitoring()
    }

    func startMonitoring() {
        refresh()
        restartTimer()

        // Listen for thermal state changes (event-driven)
        thermalService.startMonitoring { [weak self] newState in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.thermalInfo.state = newState
                if newState == .serious || newState == .critical {
                    self.sendThermalAlert(state: newState)
                }
            }
        }
    }

    private func restartTimer() {
        refreshTimer?.invalidate()
        let interval = appSettings.refreshIntervalSystem
        currentInterval = interval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.appSettings.refreshIntervalSystem != self.currentInterval {
                    self.restartTimer()
                }
                self.refresh()
            }
        }
    }

    func refresh() {
        let previousHealth = batteryInfo.healthPercent
        batteryInfo = batteryService.getBatteryInfo()
        thermalInfo = thermalService.getThermalInfo()

        // Check battery health drop
        if batteryInfo.healthPercent < appSettings.batteryHealthThreshold,
           previousHealth >= appSettings.batteryHealthThreshold {
            sendBatteryHealthAlert()
        }

        Task.detached { [weak self] in
            guard let self else { return }
            let processes = await self.networkService.getTopProcesses(limit: 5)
            await MainActor.run {
                self.topProcesses = processes
            }
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        thermalService.stopMonitoring()
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendThermalAlert(state: ProcessInfo.ThermalState) {
        guard appSettings.showNotifications, appSettings.notifyOnThermalWarning else { return }

        let content = UNMutableNotificationContent()
        content.title = "SentryBar: Thermal Warning"
        content.body = state == .critical
            ? "System is critically hot! Performance is severely throttled."
            : "System is getting warm. Consider closing heavy applications."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "thermal-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func sendBatteryHealthAlert() {
        guard appSettings.showNotifications, appSettings.notifyOnBatteryHealthDrop else { return }

        let content = UNMutableNotificationContent()
        content.title = "SentryBar: Battery Health"
        content.body = "Battery health dropped below \(appSettings.batteryHealthThreshold)%. Current: \(batteryInfo.healthPercent)%."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "battery-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    deinit {
        refreshTimer?.invalidate()
        thermalService.stopMonitoring()
    }
}
