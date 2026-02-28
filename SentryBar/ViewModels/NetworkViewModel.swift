import SwiftUI
import Combine
import UserNotifications

/// ViewModel for network connection monitoring
@MainActor
final class NetworkViewModel: ObservableObject {
    @Published var connections: [NetworkConnection] = []
    @Published var currentBandwidth: BandwidthSnapshot = .empty
    @Published var bandwidthHistory: [BandwidthSnapshot] = []
    @Published var isMeasuringBandwidth = false

    private let networkService = NetworkService()
    private let bandwidthService = BandwidthService()
    let appSettings: AppSettings
    let ruleStore: ConnectionRuleStore
    private var refreshTimer: Timer?
    private var currentInterval: Double = 0
    private var previouslySeenPIDs: Set<Int32> = []
    private var refreshCount: Int = 0
    private var bandwidthAlertedProcesses: Set<String> = []

    var suspiciousCount: Int {
        connections.filter(\.isSuspicious).count
    }

    var trustedCount: Int {
        connections.filter { $0.userClassification == .allowed }.count
    }

    var formattedUpload: String {
        currentBandwidth.processes.isEmpty ? "--" : currentBandwidth.formattedRateOut
    }

    var formattedDownload: String {
        currentBandwidth.processes.isEmpty ? "--" : currentBandwidth.formattedRateIn
    }

    /// Upload rate history for sparkline (bytes/sec, last 10 snapshots)
    var uploadRateHistory: [Double] {
        bandwidthHistory.map(\.rateOut)
    }

    /// Download rate history for sparkline (bytes/sec, last 10 snapshots)
    var downloadRateHistory: [Double] {
        bandwidthHistory.map(\.rateIn)
    }

    /// Connections sorted: blocked first, then suspicious, then normal, then trusted
    var sortedConnections: [NetworkConnection] {
        connections.sorted { a, b in sortPriority(a) < sortPriority(b) }
    }

    init(appSettings: AppSettings, ruleStore: ConnectionRuleStore) {
        self.appSettings = appSettings
        self.ruleStore = ruleStore
        startMonitoring()
    }

    func startMonitoring() {
        refresh()
        restartTimer()
    }

    private func restartTimer() {
        refreshTimer?.invalidate()
        let interval = appSettings.refreshIntervalNetwork
        currentInterval = interval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.appSettings.refreshIntervalNetwork != self.currentInterval {
                    self.restartTimer()
                }
                self.refresh()
            }
        }
    }

    func refresh() {
        refreshCount += 1

        // Determine if we should measure bandwidth this cycle
        // For fast intervals (<10s), measure every other cycle to give nettop time
        let shouldMeasureBandwidth = !isMeasuringBandwidth &&
            (appSettings.refreshIntervalNetwork >= 10 || refreshCount % 2 == 0)

        if shouldMeasureBandwidth {
            isMeasuringBandwidth = true
        }

        Task.detached { [weak self] in
            guard let self else { return }

            // Run connections and bandwidth in parallel
            async let connectionsResult = self.networkService.getConnections()
            async let bandwidthResult: BandwidthSnapshot = {
                if shouldMeasureBandwidth {
                    return await self.bandwidthService.measureBandwidth()
                }
                return await MainActor.run { self.currentBandwidth }
            }()

            let newConnections = await connectionsResult
            let bandwidth = await bandwidthResult

            await MainActor.run {
                self.isMeasuringBandwidth = false

                // Apply rules and bandwidth to connections
                let classified = newConnections.map { conn -> NetworkConnection in
                    var c = conn
                    if let rule = self.ruleStore.ruleFor(connection: conn) {
                        c.userClassification = rule.ruleType
                    }
                    // Match bandwidth data by PID or process name
                    if let bw = bandwidth.processes.first(where: {
                        $0.pid == conn.pid || $0.processName == conn.processName
                    }) {
                        c.bytesIn = bw.bytesIn
                        c.bytesOut = bw.bytesOut
                    }
                    return c
                }

                // Suspicious connection alerts
                let currentPIDs = Set(classified.map(\.pid))
                let newBlocked = classified.filter { $0.userClassification == .blocked && !self.previouslySeenPIDs.contains($0.pid) }
                for conn in newBlocked {
                    let rule = self.ruleStore.ruleFor(connection: conn)
                    self.sendSuspiciousAlert(count: 1, note: rule?.note, processName: conn.processName)
                }
                let newUnclassifiedSuspicious = classified.filter {
                    $0.userClassification == nil && $0.heuristicSuspicious && !self.previouslySeenPIDs.contains($0.pid)
                }
                if !newUnclassifiedSuspicious.isEmpty {
                    self.sendSuspiciousAlert(count: newUnclassifiedSuspicious.count, note: nil, processName: nil)
                }
                self.previouslySeenPIDs = currentPIDs

                // Update bandwidth
                if shouldMeasureBandwidth {
                    self.currentBandwidth = bandwidth
                    self.bandwidthHistory.append(bandwidth)
                    if self.bandwidthHistory.count > 10 {
                        self.bandwidthHistory.removeFirst(self.bandwidthHistory.count - 10)
                    }
                    self.checkBandwidthAlerts(bandwidth)
                }

                self.connections = classified
            }
        }
    }

    func killProcess(pid: Int32) {
        Task.detached { [weak self] in
            guard let self else { return }
            let success = await self.networkService.killProcess(pid: pid)
            if success {
                await MainActor.run {
                    self.connections.removeAll { $0.pid == pid }
                }
            }
        }
    }

    /// Re-apply rules to current connections (after a rule is added/removed)
    func reapplyRules() {
        connections = connections.map { conn in
            var c = conn
            c.userClassification = nil
            if let rule = ruleStore.ruleFor(connection: c) {
                c.userClassification = rule.ruleType
            }
            return c
        }
    }

    // MARK: - Context Menu Actions

    func trustProcess(_ processName: String) {
        ruleStore.addRule(ConnectionRule(ruleType: .allowed, matchField: .processName, matchValue: processName))
        reapplyRules()
    }

    func trustAddress(_ address: String) {
        ruleStore.addRule(ConnectionRule(ruleType: .allowed, matchField: .remoteAddress, matchValue: address))
        reapplyRules()
    }

    func blockProcess(_ processName: String) {
        ruleStore.addRule(ConnectionRule(ruleType: .blocked, matchField: .processName, matchValue: processName))
        reapplyRules()
    }

    func blockAddress(_ address: String) {
        ruleStore.addRule(ConnectionRule(ruleType: .blocked, matchField: .remoteAddress, matchValue: address))
        reapplyRules()
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Bandwidth Alerts

    private func checkBandwidthAlerts(_ snapshot: BandwidthSnapshot) {
        guard appSettings.showNotifications, appSettings.notifyOnHighBandwidth else { return }
        let thresholdBytes = UInt64(appSettings.highBandwidthThresholdMB) * 1024 * 1024

        for process in snapshot.processes {
            if process.totalBytes > thresholdBytes, !bandwidthAlertedProcesses.contains(process.processName) {
                bandwidthAlertedProcesses.insert(process.processName)
                sendBandwidthAlert(processName: process.processName, bytes: process.totalBytes)
            } else if process.totalBytes <= thresholdBytes {
                bandwidthAlertedProcesses.remove(process.processName)
            }
        }
    }

    // MARK: - Notifications

    private func sendSuspiciousAlert(count: Int, note: String?, processName: String?) {
        guard appSettings.showNotifications, appSettings.notifyOnSuspiciousConnection else { return }

        let content = UNMutableNotificationContent()
        content.title = "SentryBar: Suspicious Connections"
        if let name = processName, let note {
            content.body = "Blocked connection from \(name): \(note)"
        } else if let name = processName {
            content.body = "Blocked connection detected from \(name)."
        } else {
            content.body = "\(count) suspicious outbound connection(s) detected. Tap to review."
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "suspicious-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func sendBandwidthAlert(processName: String, bytes: UInt64) {
        let content = UNMutableNotificationContent()
        content.title = "SentryBar: High Bandwidth"
        let rate = currentBandwidth.duration > 0
            ? formatRate(Double(bytes) / currentBandwidth.duration)
            : formatBytes(bytes)
        content.body = "\(processName) is using \(rate)."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "bandwidth-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func sortPriority(_ conn: NetworkConnection) -> Int {
        switch conn.userClassification {
        case .blocked: return 0
        case nil where conn.heuristicSuspicious: return 1
        case nil: return 2
        case .allowed: return 3
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
