import Foundation

enum RuleType: String, Codable, CaseIterable {
    case allowed
    case blocked
}

enum MatchField: String, Codable, CaseIterable {
    case processName
    case remoteAddress
    case remotePort

    var label: String {
        switch self {
        case .processName: return "Process Name"
        case .remoteAddress: return "Remote Address"
        case .remotePort: return "Port"
        }
    }

    var icon: String {
        switch self {
        case .processName: return "person.fill"
        case .remoteAddress: return "globe"
        case .remotePort: return "number"
        }
    }
}

struct ConnectionRule: Codable, Identifiable, Equatable {
    let id: UUID
    let ruleType: RuleType
    let matchField: MatchField
    let matchValue: String
    var note: String?
    let createdAt: Date

    init(ruleType: RuleType, matchField: MatchField, matchValue: String, note: String? = nil) {
        self.id = UUID()
        self.ruleType = ruleType
        self.matchField = matchField
        self.matchValue = matchValue
        self.note = note
        self.createdAt = Date()
    }
}

// MARK: - Rule Store

final class ConnectionRuleStore: ObservableObject {
    @Published var rules: [ConnectionRule] = []

    private var fileURL: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SentryBar/rules.json")
        }
        let dir = appSupport.appendingPathComponent("SentryBar", isDirectory: true)
        return dir.appendingPathComponent("rules.json")
    }

    init() {
        loadRules()
    }

    func loadRules() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            rules = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            rules = try JSONDecoder().decode([ConnectionRule].self, from: data)
        } catch {
            rules = []
        }
    }

    func saveRules() {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(rules)
            try data.write(to: fileURL, options: .atomic)
            // Set restrictive permissions: owner read/write only
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // Silently fail — rules will reload from disk next launch
        }
    }

    func addRule(_ rule: ConnectionRule) {
        rules.append(rule)
        saveRules()
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        saveRules()
    }

    func removeRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        saveRules()
    }

    func clearAllRules() {
        rules.removeAll()
        saveRules()
    }

    /// Finds the first matching rule for a given connection
    func ruleFor(connection: NetworkConnection) -> ConnectionRule? {
        rules.first { rule in
            switch rule.matchField {
            case .processName:
                return connection.processName == rule.matchValue
            case .remoteAddress:
                return connection.remoteAddress == rule.matchValue
            case .remotePort:
                return connection.remotePort == rule.matchValue
            }
        }
    }

    func isAllowed(_ connection: NetworkConnection) -> Bool {
        ruleFor(connection: connection)?.ruleType == .allowed
    }

    func isBlocked(_ connection: NetworkConnection) -> Bool {
        ruleFor(connection: connection)?.ruleType == .blocked
    }

    var allowedCount: Int {
        rules.filter { $0.ruleType == .allowed }.count
    }

    var blockedCount: Int {
        rules.filter { $0.ruleType == .blocked }.count
    }
}
