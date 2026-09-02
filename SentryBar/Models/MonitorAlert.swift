import Foundation

/// How much a finding should interrupt.
enum AlertSeverity: Int, Comparable, Codable, CaseIterable {
    case info = 0
    case notice = 1
    case warning = 2

    static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .info:    return "Info"
        case .notice:  return "Notice"
        case .warning: return "Warning"
        }
    }

    var symbol: String {
        switch self {
        case .info:    return "info.circle"
        case .notice:  return "exclamationmark.circle"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

/// One thing worth telling the user about.
struct MonitorAlert: Identifiable, Equatable {
    let id: UUID
    /// Stable identity for deduplication — the same condition always produces
    /// the same key, so it can be suppressed, snoozed and counted.
    let key: String
    let type: NotificationType
    let severity: AlertSeverity
    let title: String
    let body: String
    /// What the user can actually do about it. An alert with no action is noise.
    let suggestion: String?
    let firstSeen: Date
    var lastSeen: Date
    var occurrences: Int
    var acknowledged: Bool

    init(
        key: String,
        type: NotificationType,
        severity: AlertSeverity,
        title: String,
        body: String,
        suggestion: String? = nil,
        at moment: Date = Date()
    ) {
        self.id = UUID()
        self.key = key
        self.type = type
        self.severity = severity
        self.title = title
        self.body = body
        self.suggestion = suggestion
        self.firstSeen = moment
        self.lastSeen = moment
        self.occurrences = 1
        self.acknowledged = false
    }

    static func == (lhs: MonitorAlert, rhs: MonitorAlert) -> Bool { lhs.key == rhs.key }

    var repeatedLabel: String? {
        occurrences > 1 ? "seen \(occurrences)×" : nil
    }
}

/// What the engine decided to do with a raised alert.
enum AlertDecision: Equatable {
    /// Show it. This is the only case that reaches Notification Center.
    case deliver(MonitorAlert)
    /// Already delivered recently; the existing entry's counter was bumped.
    case coalesced(key: String, occurrences: Int)
    /// Suppressed because the user snoozed this key or this type.
    case snoozed(key: String, until: Date)
    /// Suppressed because too many alerts have been delivered in this window.
    case rateLimited(key: String, deliveredInWindow: Int)
    /// Below the user's minimum severity.
    case belowThreshold(key: String)
}

/// Decides what actually reaches the user.
///
/// SentryBar's whole value is the alert, so the alert has to be worth reading.
/// Before this type there was a raw counter and a fixed cooldown; a machine that
/// stayed warm produced one notification per polling interval, forever.
///
/// The rules:
///
/// - **Deduplicate by key.** The same condition never produces two
///   notifications; the second occurrence increments a counter on the first.
/// - **Re-notify only after `repeatInterval`,** and only if the condition is
///   still true, so a persistent problem reminds you occasionally rather than
///   constantly.
/// - **Rate limit globally.** At most `maxPerWindow` notifications per
///   `windowLength`, so a burst of new connections cannot bury the machine.
/// - **Respect snoozes**, per key and per type.
/// - **Respect a severity floor**, so someone who only wants warnings gets only
///   warnings.
///
/// Everything the engine decides is returned as an `AlertDecision`, so the log
/// can show *why* something was not shown — which is the part users complain
/// about when a monitoring tool goes quiet.
final class AlertEngine {

    var minimumSeverity: AlertSeverity
    let repeatInterval: TimeInterval
    let windowLength: TimeInterval
    let maxPerWindow: Int

    private(set) var active: [String: MonitorAlert] = [:]
    private var lastDelivered: [String: Date] = [:]
    private var snoozedKeys: [String: Date] = [:]
    private var snoozedTypes: [NotificationType: Date] = [:]
    private var deliveryTimestamps: [Date] = []

    init(
        minimumSeverity: AlertSeverity = .notice,
        repeatInterval: TimeInterval = 30 * 60,
        windowLength: TimeInterval = 5 * 60,
        maxPerWindow: Int = 6
    ) {
        self.minimumSeverity = minimumSeverity
        self.repeatInterval = repeatInterval
        self.windowLength = windowLength
        self.maxPerWindow = maxPerWindow
    }

    // MARK: - Raising

    @discardableResult
    func raise(_ alert: MonitorAlert, now: Date = Date()) -> AlertDecision {
        if alert.severity < minimumSeverity {
            return .belowThreshold(key: alert.key)
        }
        if let until = snoozedTypes[alert.type], until > now {
            return .snoozed(key: alert.key, until: until)
        }
        if let until = snoozedKeys[alert.key], until > now {
            return .snoozed(key: alert.key, until: until)
        }

        if var existing = active[alert.key] {
            existing.occurrences += 1
            existing.lastSeen = now
            active[alert.key] = existing

            let last = lastDelivered[alert.key] ?? .distantPast
            guard now.timeIntervalSince(last) >= repeatInterval else {
                return .coalesced(key: alert.key, occurrences: existing.occurrences)
            }
            guard admitToWindow(now: now) else {
                return .rateLimited(key: alert.key, deliveredInWindow: deliveryTimestamps.count)
            }
            lastDelivered[alert.key] = now
            return .deliver(existing)
        }

        guard admitToWindow(now: now) else {
            active[alert.key] = alert
            return .rateLimited(key: alert.key, deliveredInWindow: deliveryTimestamps.count)
        }
        active[alert.key] = alert
        lastDelivered[alert.key] = now
        return .deliver(alert)
    }

    private func admitToWindow(now: Date) -> Bool {
        let cutoff = now.addingTimeInterval(-windowLength)
        deliveryTimestamps.removeAll { $0 < cutoff }
        guard deliveryTimestamps.count < maxPerWindow else { return false }
        deliveryTimestamps.append(now)
        return true
    }

    // MARK: - Clearing and snoozing

    /// The condition is no longer true. The next occurrence is a fresh alert.
    func clear(key: String) {
        active.removeValue(forKey: key)
        lastDelivered.removeValue(forKey: key)
    }

    /// Keep only the keys still present, clearing everything else.
    func retainOnly(keys: Set<String>) {
        for key in active.keys where !keys.contains(key) {
            clear(key: key)
        }
    }

    func acknowledge(key: String) {
        active[key]?.acknowledged = true
    }

    func snooze(key: String, for duration: TimeInterval, now: Date = Date()) {
        snoozedKeys[key] = now.addingTimeInterval(duration)
    }

    func snooze(type: NotificationType, for duration: TimeInterval, now: Date = Date()) {
        snoozedTypes[type] = now.addingTimeInterval(duration)
    }

    func unsnooze(key: String) { snoozedKeys.removeValue(forKey: key) }
    func unsnooze(type: NotificationType) { snoozedTypes.removeValue(forKey: type) }

    func isSnoozed(key: String, now: Date = Date()) -> Bool {
        if let until = snoozedKeys[key], until > now { return true }
        return false
    }

    /// Alerts currently considered live, worst and newest first.
    var currentAlerts: [MonitorAlert] {
        active.values.sorted {
            ($0.severity, $0.lastSeen) > ($1.severity, $1.lastSeen)
        }
    }

    var unacknowledgedCount: Int {
        active.values.filter { !$0.acknowledged }.count
    }
}
