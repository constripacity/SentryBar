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
            // Browsers
            "Safari", "Google Chrome", "Google Chrome Helper",
            "Firefox", "Brave Browser", "Arc", "Microsoft Edge",
            "Opera", "Vivaldi", "Orion",
            // Communication
            "Slack", "Discord", "Messages", "FaceTime", "zoom.us",
            "Telegram", "WhatsApp", "Signal", "Microsoft Teams",
            "Skype", "Webex",
            // Email
            "Mail", "Outlook", "Spark", "Thunderbird",
            // Media & streaming
            "Spotify", "Music", "Podcasts", "TV", "VLC",
            // Cloud & sync
            "Finder", "Dropbox", "Google Drive", "OneDrive",
            "iCloud", "Box",
            // Productivity
            "Notes", "Maps", "Calendar", "Reminders",
            "Notion", "Obsidian", "Bear",
            // Security & VPN
            "1Password", "Bitwarden",
            // Development
            "Code Helper", "node", "python3", "python", "curl",
            "git-remote-https", "Xcode", "Docker", "Postman",
            "npm", "yarn", "ruby", "php", "java", "go",
            "Terminal", "iTerm2", "Warp", "ssh", "wget",
            // Apple system apps
            "App Store", "System Preferences", "System Settings",
            "Preview", "TextEdit", "Photo Booth",
            // Gaming
            "Steam", "Steam Helper"
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
