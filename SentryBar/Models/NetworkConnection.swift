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

    /// Effective flagged status, accounting for an explicit user rule.
    ///
    /// A user rule always wins. Absent one, this reflects whatever the baseline
    /// concluded — which is `false` until the baseline has warmed up, so a fresh
    /// install is quiet rather than alarming.
    var isSuspicious: Bool {
        switch userClassification {
        case .allowed: return false
        case .blocked: return true
        case nil: return heuristicSuspicious
        }
    }

    /// Whether this connection leaves the local network.
    var isExternal: Bool { !Self.isPrivateAddress(remoteAddress) }

    /// A note about the protocol in use, when there is one worth making.
    var protocolNote: String? { Self.protocolNote(forPort: remotePort) }

    /// A stable identity for alerting and rule matching. Unlike `id`, this is
    /// the same across refreshes for the same process and destination, which is
    /// what makes deduplication possible.
    var alertKey: String {
        "conn:\(processName):\(ConnectionFingerprint.generalise(address: remoteAddress)):\(remotePort)"
    }

    /// Raw heuristic result (ignoring user rules)
    /// Whether the baseline considers this destination new for this process.
    ///
    /// Mutable because it is filled in *after* parsing, by
    /// `ConnectionBaseline`. The parser deliberately knows nothing about
    /// suspicion — that is a property of this machine's history, not of the
    /// socket table.
    var heuristicSuspicious: Bool

    /// Human-friendly label for the connection's remote port
    var serviceLabel: String {
        switch remotePort {
        case "443":         return "Secure web (HTTPS)"
        case "80":          return "Web (HTTP)"
        case "53":          return "DNS lookup"
        case "993", "143":  return "Email (IMAP)"
        case "587", "465", "25": return "Email (SMTP)"
        case "22":          return "SSH"
        case "5228":        return "Push notifications"
        case "5223":        return "Push notifications"
        case "3478", "3479": return "Video/voice call"
        case "8443":        return "Secure web (alt)"
        case "8080":        return "Web proxy"
        case "123":         return "Time sync (NTP)"
        case "*":           return "Listening"
        default:
            if let port = Int(remotePort), port > 49152 {
                return "High port \(remotePort)"
            }
            return "Port \(remotePort)"
        }
    }

    /// Known system processes that should not be killable
    static let systemProcesses: Set<String> = [
        // Core system
        "kernel_task", "launchd", "WindowServer", "loginwindow",
        "mds", "mds_stores", "trustd", "syslogd", "configd",
        "securityd", "coreauthd", "UserEventAgent", "distnoted",
        // Networking
        "rapportd", "sharingd", "identityservicesd", "symptomsd",
        "networkd", "bluetoothd", "airportd", "mDNSResponder",
        "netbiosd", "WiFiAgent",
        // Apple services
        "apsd", "cloudd", "nsurlsessiond", "CommCenter", "bird",
        "locationd", "timed", "assistantd", "siriknowledged",
        "searchpartyd", "findmydeviced", "familycircled",
        // Media & sync
        "mediaremoted", "AMPDeviceDiscoveryAgent", "photoanalysisd",
        "IMTransferAgent", "calaccessd", "remindd",
        // Updates & store
        "softwareupdated", "storeassetd", "storedownloadd",
        // Misc daemons
        "accountsd", "akd", "biomesyncd", "coreduetd",
        "suggestd", "parsecd", "lsd", "mdworker", "usernoted"
    ]

    /// Ports whose *presence* is worth a note, with the honest reason why.
    ///
    /// The previous version treated a fixed list of ports as "suspicious" and,
    /// separately, flagged **any** connection above port 49152 from a process
    /// missing from a 60-entry hard-coded allowlist. On a real Mac that second
    /// rule fires on WebRTC, QUIC, game servers, CDNs, every Homebrew tool and
    /// every app the list had not heard of. A monitor that cries wolf on a
    /// hundred normal connections teaches its user to ignore it, which is worse
    /// than not alerting at all.
    ///
    /// What remains here is a small set of ports where an *unencrypted* or
    /// *administrative* protocol is in use. That is a statement of fact the user
    /// can act on, not an accusation.
    static let notableProtocolPorts: [String: String] = [
        "23":   "Telnet — this connection is not encrypted",
        "21":   "FTP — credentials on this protocol are sent in the clear",
        "25":   "SMTP — mail submission, often unencrypted",
        "110":  "POP3 — unencrypted mail retrieval",
        "143":  "IMAP — unencrypted unless upgraded with STARTTLS",
        "3389": "Remote Desktop",
        "5900": "VNC screen sharing",
        "445":  "SMB file sharing",
        "22":   "SSH — an encrypted administrative session",
    ]

    /// Whether the port carries something worth mentioning, and why.
    static func protocolNote(forPort port: String) -> String? {
        notableProtocolPorts[port]
    }

    /// Whether this connection leaves the local network.
    ///
    /// A connection to `192.168.x.x` is a printer or a NAS; a connection to a
    /// public address is the one worth looking at. The old model made no
    /// distinction, which is a large part of why it was noisy.
    static func isPrivateAddress(_ address: String) -> Bool {
        if address.hasPrefix("127.") || address == "::1" || address == "localhost" { return true }
        if address.hasPrefix("10.") || address.hasPrefix("192.168.") { return true }
        if address.hasPrefix("169.254.") || address.lowercased().hasPrefix("fe80:") { return true }
        if address.hasPrefix("172.") {
            let parts = address.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        if address.lowercased().hasPrefix("fd") || address.lowercased().hasPrefix("fc") {
            return true
        }
        return false
    }

    /// Deprecated. Suspicion is no longer decided by a hard-coded list; it comes
    /// from `ConnectionBaseline`, which learns what is normal *on this machine*.
    ///
    /// Retained returning `false` so any remaining caller degrades to "not
    /// suspicious" rather than to the old flood of false positives.
    @available(*, deprecated, message: "Use ConnectionBaseline.observe(_:) instead")
    static func evaluateSuspicion(
        processName: String, remotePort: String, remoteAddress: String
    ) -> Bool {
        false
    }

}

/// Represents a running process with its CPU usage
struct AppProcess: Identifiable {
    let id = UUID()
    let name: String
    let pid: Int32
    let cpuUsage: Double
}
