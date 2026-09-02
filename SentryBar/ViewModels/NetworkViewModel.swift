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
    @Published var sessionTotalIn: UInt64 = 0
    @Published var sessionTotalOut: UInt64 = 0
    @Published var sessionAppUsage: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

    private let networkService = NetworkService()
    private let bandwidthService = BandwidthService()
    let appSettings: AppSettings
    let ruleStore: ConnectionRuleStore
    private var refreshTimer: Timer?
    private var currentInterval: Double = 0
    private var previouslySeenPIDs: Set<Int32> = []
    private var refreshCount: Int = 0
    private let notificationLog: NotificationLog

    /// What normal looks like on *this* Mac. See `ConnectionBaseline`.
    let baseline: ConnectionBaseline
    /// Decides what actually reaches Notification Center: deduplication, repeat
    /// intervals, a global rate limit and snoozes. This replaces a pair of
    /// `lastAlertTime` fields and a flat 60-second cooldown, which meant a
    /// machine in a steady bad state produced one notification per interval
    /// forever, and two unrelated conditions could suppress each other.
    let alerts = AlertEngine()

    /// Findings from the most recent refresh, newest first.
    @Published private(set) var baselineFindings: [BaselineFinding] = []
    /// What the baseline holds, for the Settings list.
    ///
    /// Published rather than computed on demand: `ConnectionBaseline` is a
    /// plain class, so a view reading through it would never be told the value
    /// changed. `baselineStatus` has the same problem and is refreshed here
    /// too.
    @Published private(set) var learnedProcesses: [LearnedProcess] = []
    @Published private(set) var baselineStatus: String = ""
    /// A message to show instead of an empty list when a reading failed.
    @Published private(set) var readingProblem: String?
    /// The outcome of the most recent attempt to end a process.
    @Published var lastTerminateOutcome: TerminateOutcome?

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

    var formattedSessionIn: String { formatBytes(sessionTotalIn) }
    var formattedSessionOut: String { formatBytes(sessionTotalOut) }
    var formattedSessionTotal: String { formatBytes(sessionTotalIn + sessionTotalOut) }

    /// Top apps by cumulative session data usage, sorted by total bytes
    var topSessionApps: [(name: String, bytesIn: UInt64, bytesOut: UInt64)] {
        sessionAppUsage
            .map { (name: $0.key, bytesIn: $0.value.bytesIn, bytesOut: $0.value.bytesOut) }
            .sorted { ($0.bytesIn + $0.bytesOut) > ($1.bytesIn + $1.bytesOut) }
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

    init(
        appSettings: AppSettings,
        ruleStore: ConnectionRuleStore,
        notificationLog: NotificationLog,
        baseline: ConnectionBaseline = ConnectionBaseline()
    ) {
        self.appSettings = appSettings
        self.ruleStore = ruleStore
        self.notificationLog = notificationLog
        self.baseline = baseline
        startMonitoring()
    }

    /// How far through its learning period the baseline is, described honestly
    /// rather than pretending it knows things it does not.
    private func describeBaseline() -> String {
        if baseline.isWarmedUp {
            return "Learned \(baseline.knownEndpointCount) destinations. "
                 + "New ones are flagged."
        }
        let percent = Int(baseline.learningProgress * 100)
        return "Still learning what is normal (\(percent)%). "
             + "Nothing is flagged as new until this finishes."
    }

    private func refreshBaselineSummary() {
        baselineStatus = describeBaseline()
        learnedProcesses = baseline.learnedProcesses()
    }

    /// Forget everything and start the learning period again.
    ///
    /// The control for this lives in Settings. It matters after a false start
    /// — the baseline learned during a week of unusual activity is worse than
    /// no baseline, because it has quietly accepted the unusual as normal.
    func resetBaseline() {
        baseline.reset()
        baselineFindings = []
        refreshBaselineSummary()
    }

    /// Forget one process, for a legitimate app that changed its endpoints.
    func forgetBaseline(process: String) {
        baseline.forget(process: process)
        baselineFindings.removeAll { $0.fingerprint.process == process }
        refreshBaselineSummary()
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

                self.readingProblem = self.networkService.lastResult.userFacingMessage

                // Learn from what is on the wire, and find out what is new. Only
                // external connections are baselined: a link to the printer at
                // 192.168.1.30 is not an anomaly worth anyone's attention.
                let external = classified.filter(\.isExternal)
                let findings = self.baseline.observe(external)
                self.baselineFindings = findings

                let flagged = Set(findings.map(\.fingerprint))
                let annotated = classified.map { conn -> NetworkConnection in
                    var c = conn
                    if c.userClassification == nil {
                        let fingerprint = ConnectionFingerprint(
                            process: c.processName,
                            address: c.remoteAddress,
                            port: c.remotePort
                        )
                        c.heuristicSuspicious = flagged.contains(fingerprint)
                    }
                    return c
                }

                self.refreshBaselineSummary()
                self.raiseConnectionAlerts(for: annotated, findings: findings)
                self.previouslySeenPIDs = Set(annotated.map(\.pid))

                // Update bandwidth
                if shouldMeasureBandwidth {
                    self.currentBandwidth = bandwidth
                    self.bandwidthHistory.append(bandwidth)
                    if self.bandwidthHistory.count > 10 {
                        self.bandwidthHistory.removeFirst(self.bandwidthHistory.count - 10)
                    }

                    // Accumulate session totals
                    self.sessionTotalIn += bandwidth.totalBytesIn
                    self.sessionTotalOut += bandwidth.totalBytesOut
                    for process in bandwidth.processes {
                        let existing = self.sessionAppUsage[process.processName] ?? (bytesIn: 0, bytesOut: 0)
                        self.sessionAppUsage[process.processName] = (
                            bytesIn: existing.bytesIn + process.bytesIn,
                            bytesOut: existing.bytesOut + process.bytesOut
                        )
                    }

                    self.checkBandwidthAlerts(bandwidth)
                }

                self.connections = annotated
            }
        }
    }

    /// Asks a process to quit.
    ///
    /// The process's name is passed alongside its PID so the service can refuse
    /// if the number has since been recycled by something else — see
    /// `NetworkService.terminate(pid:expectedName:)`. The outcome is published
    /// rather than swallowed, because "nothing happened and nobody said why" is
    /// the worst possible response to a button that ends processes.
    func terminate(connection: NetworkConnection) {
        let pid = connection.pid
        let name = connection.processName
        Task.detached { [weak self] in
            guard let self else { return }
            let outcome = await self.networkService.terminate(pid: pid, expectedName: name)
            await MainActor.run {
                self.lastTerminateOutcome = outcome
                if outcome.succeeded {
                    self.connections.removeAll { $0.pid == pid }
                    self.notificationLog.add(
                        type: .suspicious,
                        title: "Asked \(name) to quit",
                        body: "SentryBar sent SIGTERM to PID \(pid)."
                    )
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

        var stillOver: Set<String> = []
        for process in snapshot.processes where process.totalBytes > thresholdBytes {
            let key = "bandwidth:\(process.processName)"
            stillOver.insert(key)
            let rate = snapshot.duration > 0
                ? formatRate(Double(process.totalBytes) / snapshot.duration)
                : formatBytes(process.totalBytes)
            deliver(
                MonitorAlert(
                    key: key,
                    type: .bandwidth,
                    severity: .notice,
                    title: "\(process.processName) is using a lot of bandwidth",
                    body: "\(process.processName) moved \(formatBytes(process.totalBytes)) "
                        + "in the last sample (\(rate)).",
                    suggestion: "If this is unexpected, check what it is connected to in the "
                              + "Network tab before ending it."
                )
            )
        }
        // Anything no longer over the threshold stops being an active alert, so
        // the next time it happens it is genuinely new.
        for key in alerts.active.keys where key.hasPrefix("bandwidth:") && !stillOver.contains(key) {
            alerts.clear(key: key)
        }
    }

    /// Turns rule matches and baseline findings into alerts.
    private func raiseConnectionAlerts(
        for connections: [NetworkConnection], findings: [BaselineFinding]
    ) {
        guard appSettings.showNotifications, appSettings.notifyOnSuspiciousConnection else { return }

        var live: Set<String> = []

        for conn in connections where conn.userClassification == .blocked {
            live.insert(conn.alertKey)
            let note = ruleStore.ruleFor(connection: conn)?.note
            deliver(
                MonitorAlert(
                    key: conn.alertKey,
                    type: .suspicious,
                    severity: .warning,
                    title: "\(conn.processName) connected to a blocked destination",
                    body: note.map { "\(conn.remoteAddress):\(conn.remotePort) — \($0)" }
                        ?? "\(conn.remoteAddress):\(conn.remotePort) matches one of your block rules.",
                    suggestion: "SentryBar watches but never blocks traffic. To actually stop "
                              + "this connection, quit the app or use a firewall such as LuLu."
                )
            )
        }

        for finding in findings {
            let key = "new:\(finding.fingerprint.description)"
            live.insert(key)
            deliver(
                MonitorAlert(
                    key: key,
                    type: .suspicious,
                    severity: .notice,
                    title: finding.headline,
                    body: finding.detail,
                    suggestion: "If this is expected, right-click the connection and trust "
                              + "\(finding.fingerprint.process) so it stops being reported."
                )
            )
        }

        for conn in connections where conn.isExternal {
            guard let note = conn.protocolNote, conn.userClassification == nil else { continue }
            let key = "protocol:\(conn.processName):\(conn.remotePort)"
            live.insert(key)
            deliver(
                MonitorAlert(
                    key: key,
                    type: .suspicious,
                    severity: .info,
                    title: "\(conn.processName) is using \(conn.serviceLabel)",
                    body: note,
                    suggestion: "This is a statement of fact about the protocol, not an "
                              + "accusation. Modern alternatives are encrypted."
                )
            )
        }

        alerts.retainOnly(
            keys: live.union(alerts.active.keys.filter { $0.hasPrefix("bandwidth:") })
        )
    }

    /// Sends an alert to Notification Center if the engine says it should be seen.
    ///
    /// Every decision is written to the notification log, including the
    /// suppressions, so a user who wonders why SentryBar has gone quiet can find
    /// out instead of assuming it is broken.
    private func deliver(_ alert: MonitorAlert) {
        switch alerts.raise(alert) {
        case let .deliver(delivered):
            let content = UNMutableNotificationContent()
            content.title = delivered.title
            content.body = delivered.suggestion.map { "\(delivered.body)\n\n\($0)" }
                ?? delivered.body
            content.sound = delivered.severity == .warning ? .default : nil
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    identifier: delivered.key, content: content, trigger: nil
                )
            )
            notificationLog.add(type: delivered.type, title: delivered.title, body: delivered.body)

        case let .coalesced(key, occurrences):
            logger("Repeat of \(key) (\(occurrences)×) — not re-notifying yet.")
        case let .rateLimited(key, count):
            logger("Rate limit reached (\(count) in the last few minutes); held \(key).")
        case let .snoozed(key, until):
            logger("\(key) is snoozed until \(until.formatted(date: .omitted, time: .shortened)).")
        case .belowThreshold:
            break
        }
    }

    private func logger(_ message: String) {
        #if DEBUG
        print("[SentryBar alerts] \(message)")
        #endif
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
