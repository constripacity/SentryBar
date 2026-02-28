import Foundation

struct NetworkConnection: Identifiable {
    let id = UUID()
    let processName: String
    let pid: Int32
    let remoteAddress: String
    let remotePort: String
    let `protocol`: String // TCP or UDP
    let state: String // ESTABLISHED, LISTEN, etc.
    var userClassification: RuleType? // nil = unclassified, uses heuristic
    var bytesIn: UInt64? // per-interval bandwidth (from nettop)
    var bytesOut: UInt64? // per-interval bandwidth (from nettop)
    let canKill: Bool

    /// Effective suspicious status accounting for user classification
    var isSuspicious: Bool {
        switch userClassification {
        case .allowed: return false
        case .blocked: return true
        case nil: return heuristicSuspicious
        }
    }

    /// Raw heuristic result (ignoring user rules)
    let heuristicSuspicious: Bool

    /// Known system processes that should not be killable
    static let systemProcesses: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow",
        "mds", "mds_stores", "trustd", "syslogd", "configd"
    ]

    /// Ports commonly associated with suspicious activity
    static let suspiciousPorts: Set<String> = [
        "4444", "5555", "6666", "1337", "31337", "8888"
    ]

    /// Check if a connection might be suspicious based on heuristics
    static func evaluateSuspicion(processName: String, remotePort: String, remoteAddress: String) -> Bool {
        // Known suspicious ports
        if suspiciousPorts.contains(remotePort) { return true }

        // Non-standard high ports from unknown processes
        if let port = Int(remotePort), port > 49152, !isKnownProcess(processName) {
            return true
        }

        return false
    }

    static func isKnownProcess(_ name: String) -> Bool {
        let knownApps: Set<String> = [
            "Safari", "Google Chrome", "Firefox", "Slack", "Spotify",
            "Mail", "Messages", "FaceTime", "zoom.us", "Discord",
            "Code Helper", "node", "python3", "curl", "git-remote-https",
            "Finder", "Notes", "Music", "Podcasts", "Maps"
        ]
        return knownApps.contains(name) || systemProcesses.contains(name)
    }
}

/// Represents a running process with its CPU usage
struct AppProcess: Identifiable {
    let id = UUID()
    let name: String
    let pid: Int32
    let cpuUsage: Double
}
