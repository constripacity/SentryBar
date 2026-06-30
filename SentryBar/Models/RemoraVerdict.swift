import SwiftUI

// Codable models for the Remora engine's loopback verdict JSON (POST /triage on its FastAPI).
// Remora is the wire-level triage brain; SentryBar renders its verdict. Operating contract:
// everything here is DISPLAY DATA — the app never acts on a string Remora returns.

struct RemoraVerdict: Codable {
    let trust: String                 // "trusted" | "caution" | "hostile"
    let summary: String
    let findings: [RemoraFinding]     // already sorted severity-descending by the engine
    let stats: RemoraStats

    var riskScore: Int { stats.riskScore?.score ?? 0 }
    var band: RemoraBand { RemoraBand(stats.riskScore?.band) }
    var techniques: [RemoraTechnique] { stats.attack?.techniques ?? [] }
    var focus: String? { stats.ranking?.focus }

    var trustColor: Color {
        switch trust.lowercased() {
        case "hostile": return .red
        case "caution": return .yellow
        default: return .green
        }
    }
}

struct RemoraStats: Codable {
    let riskScore: RemoraRiskScore?
    let attack: RemoraAttack?
    let ranking: RemoraRanking?

    enum CodingKeys: String, CodingKey {
        case riskScore = "risk_score"
        case attack
        case ranking
    }
}

struct RemoraRiskScore: Codable {
    let score: Int
    let band: String
    let drivers: [RemoraDriver]
}

struct RemoraDriver: Codable, Identifiable {
    let check: String
    let severity: String
    let points: Int
    var id: String { check }
}

struct RemoraAttack: Codable {
    let techniques: [RemoraTechnique]
    let tactics: [String]
}

struct RemoraTechnique: Codable, Identifiable {
    let techniqueID: String           // MITRE id, e.g. "T1557.002" (JSON key "id")
    let name: String
    let tactic: String
    let checks: [String]
    var id: String { techniqueID }

    enum CodingKeys: String, CodingKey {
        case techniqueID = "id"
        case name, tactic, checks
    }
}

struct RemoraFinding: Codable, Identifiable {
    let check: String
    let severity: String              // lowercase: info|low|medium|high|critical
    let title: String
    let detail: String
    let recommendation: String
    var id: String { check + "|" + title }

    // `evidence` is free-form per check and deliberately not decoded.
    enum CodingKeys: String, CodingKey {
        case check, severity, title, detail, recommendation
    }
}

struct RemoraRanking: Codable {
    let focus: String?                // null when there are no findings
    let order: [String]
}

// 0-100 risk band (matches Remora's score.py bands). Drives the dial colour + the menubar icon.
enum RemoraBand: String, CaseIterable {
    case clean, low, elevated, high, critical

    init(_ raw: String?) {
        self = RemoraBand(rawValue: (raw ?? "clean").lowercased()) ?? .clean
    }

    var color: Color {
        switch self {
        case .clean:    return .teal
        case .low:      return .blue
        case .elevated: return .yellow
        case .high:     return .orange
        case .critical: return .red
        }
    }

    var label: String { rawValue.uppercased() }

    var ordinal: Int {
        switch self {
        case .clean: return 0
        case .low: return 1
        case .elevated: return 2
        case .high: return 3
        case .critical: return 4
        }
    }
}

// Finding-severity colour, matching the web client's SEV palette.
enum RemoraSeverity {
    static func color(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "critical": return .red
        case "high":     return .orange
        case "medium":   return .yellow
        case "low":      return .blue
        default:         return .gray
        }
    }
}
