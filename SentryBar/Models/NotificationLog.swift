import Foundation

enum NotificationType: String, CaseIterable {
    case thermal
    case battery
    case suspicious
    case bandwidth

    var icon: String {
        switch self {
        case .thermal:    return "thermometer.high"
        case .battery:    return "battery.25"
        case .suspicious: return "exclamationmark.triangle.fill"
        case .bandwidth:  return "arrow.up.arrow.down.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .thermal:    return "Thermal"
        case .battery:    return "Battery"
        case .suspicious: return "Suspicious"
        case .bandwidth:  return "Bandwidth"
        }
    }
}

struct NotificationLogEntry: Identifiable {
    let id: UUID
    let type: NotificationType
    let title: String
    let body: String
    let timestamp: Date

    init(type: NotificationType, title: String, body: String) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.body = body
        self.timestamp = Date()
    }
}

@MainActor
final class NotificationLog: ObservableObject {
    @Published private(set) var entries: [NotificationLogEntry] = []

    private let maxEntries = 50

    func add(type: NotificationType, title: String, body: String) {
        let entry = NotificationLogEntry(type: type, title: title, body: body)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    func clearAll() {
        entries.removeAll()
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    var count: Int {
        entries.count
    }
}
