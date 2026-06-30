import SwiftUI
import Combine
import UserNotifications

/// Owns the Remora verdict + engine reachability for the menubar. Mirrors NetworkViewModel's shape:
/// an @MainActor ObservableObject with a Timer steady-state poll (netstate-only, fanless) and an
/// on-demand rich-triage action. Fires a native notification on a band transition into high/critical.
@MainActor
final class RemoraViewModel: ObservableObject {
    @Published var verdict: RemoraVerdict?
    @Published var isReachable = false
    @Published var isRunning = false
    @Published var lastError: String?

    let appSettings: AppSettings
    private let notificationLog: NotificationLog
    private let service = RemoraService()
    private var pollTimer: Timer?
    private var currentInterval: Double = 0
    private var lastNotifiedBand: RemoraBand = .clean
    private var lastAlertTime: Date?
    private let notificationCooldown: TimeInterval = 60

    /// What the menubar status icon tints from.
    var riskBand: RemoraBand { verdict?.band ?? .clean }

    private var config: RemoraService.Config {
        RemoraService.Config(port: appSettings.remoraPort,
                             token: appSettings.remoraToken,
                             interface: appSettings.remoraInterface)
    }

    init(appSettings: AppSettings, notificationLog: NotificationLog) {
        self.appSettings = appSettings
        self.notificationLog = notificationLog
        poll()
        restartTimer()
    }

    private func restartTimer() {
        pollTimer?.invalidate()
        let interval = max(5, appSettings.refreshIntervalRemora)
        currentInterval = interval
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.appSettings.refreshIntervalRemora != self.currentInterval {
                    self.restartTimer()
                }
                self.poll()
            }
        }
    }

    /// Steady state: netstate-only reachability (no capture — fanless, safe to poll).
    func poll() {
        let cfg = config
        let service = self.service     // snapshot on the main actor (RemoraService is Sendable)
        Task.detached { [weak self] in
            let reachable = await service.ping(cfg)
            await MainActor.run { self?.isReachable = reachable }
        }
    }

    /// On-demand: the rich wire triage (needs tshark/ChmodBPF on the engine host).
    func runTriage() {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        let cfg = config
        Task { [weak self] in
            guard let self else { return }
            let result = await self.service.triage(cfg, seconds: 20)
            await MainActor.run {
                self.isRunning = false
                if let result {
                    self.verdict = result
                    self.isReachable = true
                    self.maybeNotify(result)
                } else {
                    self.lastError = "Triage failed — is the Remora engine running on "
                        + "127.0.0.1:\(cfg.port) with packet capture (ChmodBPF) enabled?"
                }
            }
        }
    }

    // MARK: - Notifications

    private func maybeNotify(_ verdict: RemoraVerdict) {
        let band = verdict.band
        defer { lastNotifiedBand = band }
        guard appSettings.showNotifications, appSettings.notifyOnRemoraVerdict else { return }
        // Only on a transition UP into high/critical (a sustained high band doesn't re-alert).
        guard band.ordinal >= RemoraBand.high.ordinal,
              band.ordinal > lastNotifiedBand.ordinal else { return }
        if let last = lastAlertTime, Date().timeIntervalSince(last) < notificationCooldown { return }
        lastAlertTime = Date()

        let content = UNMutableNotificationContent()
        content.title = "Remora: \(band.label) network risk"
        content.body = "\(verdict.summary) (risk \(verdict.riskScore)/100)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "remora-\(UUID().uuidString)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        notificationLog.add(type: .remora, title: content.title, body: content.body)
    }
}
