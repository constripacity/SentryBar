import Foundation

/// What SentryBar has learned about which processes normally talk to what.
///
/// This is the answer to the question the previous heuristic could not answer.
/// That heuristic flagged *any* connection to a port above 49152 from a process
/// missing from a hard-coded 60-entry allowlist. On a real Mac that means WebRTC
/// calls, QUIC, game servers, CDNs, every Homebrew tool and every app the
/// allowlist had never heard of — a flood of alerts that says nothing, which is
/// how a monitoring tool trains its user to ignore it.
///
/// A local behavioural baseline says something specific instead:
///
///   > Safari has connected to 63 endpoints over the last 12 days.
///   > `140.82.121.4:443` is one it has never used before.
///
/// Design constraints, all deliberate:
///
/// - **Deterministic.** No model, no scoring, no randomness. An observation is
///   either in the baseline or it is not.
/// - **Local.** The file never leaves the machine and nothing is uploaded. This
///   is a privacy tool; a baseline that phoned home would be self-defeating.
/// - **Explainable.** Every alert can name the process, the endpoint, how long
///   the baseline has been learning, and how many endpoints it already knew.
/// - **Honest about warm-up.** For the first `learningPeriod`, everything is new
///   and nothing is reported. Alerting from an empty baseline is just alerting
///   on everything.
struct ConnectionFingerprint: Hashable, Codable {
    /// The process, as reported by `lsof`.
    let process: String
    /// The remote endpoint, generalised. See `Self.generalise(address:)`.
    let endpoint: String
    /// The remote port.
    let port: String

    init(process: String, address: String, port: String) {
        self.process = process
        self.endpoint = Self.generalise(address: address)
        self.port = port
    }

    /// Reduces an address to the unit a human would recognise as "the same place".
    ///
    /// A CDN answers from a different host on every request, so recording exact
    /// addresses would mean everything is always new. The /24 (IPv4) or /48
    /// (IPv6) prefix is coarse enough that a service stays one entry, and fine
    /// enough that a genuinely different destination stands out.
    static func generalise(address: String) -> String {
        if address.contains(":") {
            let groups = address.split(separator: ":", omittingEmptySubsequences: false)
            let prefix = groups.prefix(3).joined(separator: ":")
            return prefix.isEmpty ? address : prefix + "::/48"
        }
        let octets = address.split(separator: ".")
        guard octets.count == 4 else { return address }
        return octets.prefix(3).joined(separator: ".") + ".0/24"
    }

    var description: String { "\(process) → \(endpoint):\(port)" }
}

/// One learned entry.
struct BaselineEntry: Codable {
    let firstSeen: Date
    var lastSeen: Date
    var observations: Int

    mutating func touch(at moment: Date) {
        lastSeen = moment
        observations += 1
    }
}

/// Why a connection was flagged, in words the UI can show directly.
/// One process's share of the baseline, for the Settings list.
struct LearnedProcess: Identifiable, Equatable {
    var id: String { process }
    let process: String
    let endpoints: Int
    let lastSeen: Date
}

struct BaselineFinding: Identifiable, Equatable {
    let id = UUID()
    let fingerprint: ConnectionFingerprint
    let headline: String
    let detail: String
    let firstSeen: Date

    static func == (lhs: BaselineFinding, rhs: BaselineFinding) -> Bool {
        lhs.fingerprint == rhs.fingerprint
    }
}

/// A learned, on-disk model of normal network behaviour for this Mac.
final class ConnectionBaseline {

    /// Nothing is reported as new until the baseline has been learning this long.
    let learningPeriod: TimeInterval
    /// Entries not seen for this long are forgotten, so an uninstalled app does
    /// not keep its endpoints in the baseline forever.
    let retention: TimeInterval
    /// Cap on stored fingerprints. A browser alone can produce thousands.
    let maxEntries: Int

    private(set) var startedLearning: Date
    private(set) var entries: [ConnectionFingerprint: BaselineEntry]
    private let storageURL: URL?
    private let queue = DispatchQueue(label: "com.sentrybar.baseline")

    init(
        storageURL: URL? = ConnectionBaseline.defaultStorageURL(),
        learningPeriod: TimeInterval = 3 * 24 * 60 * 60,
        retention: TimeInterval = 60 * 24 * 60 * 60,
        maxEntries: Int = 20_000
    ) {
        self.storageURL = storageURL
        self.learningPeriod = learningPeriod
        self.retention = retention
        self.maxEntries = maxEntries
        self.entries = [:]
        self.startedLearning = Date()
        load()
    }

    static func defaultStorageURL() -> URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let directory = support.appendingPathComponent("SentryBar", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory.appendingPathComponent("network-baseline.json")
    }

    // MARK: - Learning and evaluating

    /// Whether enough time has passed for "new" to mean anything.
    var isWarmedUp: Bool {
        Date().timeIntervalSince(startedLearning) >= learningPeriod
    }

    var learningProgress: Double {
        guard learningPeriod > 0 else { return 1 }
        let elapsed = Date().timeIntervalSince(startedLearning)
        return min(max(elapsed / learningPeriod, 0), 1)
    }

    var knownEndpointCount: Int { entries.count }

    func endpointCount(forProcess process: String) -> Int {
        entries.keys.filter { $0.process == process }.count
    }

    /// Records a set of live connections and returns the ones that are new.
    ///
    /// During warm-up everything is recorded and nothing is returned, which is
    /// the whole point: an empty baseline would otherwise report every
    /// connection on the machine as anomalous.
    @discardableResult
    func observe(_ connections: [NetworkConnection], now: Date = Date()) -> [BaselineFinding] {
        var findings: [BaselineFinding] = []
        let warm = isWarmedUp

        queue.sync {
            for connection in connections {
                let fingerprint = ConnectionFingerprint(
                    process: connection.processName,
                    address: connection.remoteAddress,
                    port: connection.remotePort
                )
                if var existing = entries[fingerprint] {
                    existing.touch(at: now)
                    entries[fingerprint] = existing
                    continue
                }

                entries[fingerprint] = BaselineEntry(firstSeen: now, lastSeen: now, observations: 1)
                guard warm else { continue }

                let known = entries.keys.filter { $0.process == fingerprint.process }.count - 1
                let days = Int(now.timeIntervalSince(startedLearning) / 86_400)
                findings.append(
                    BaselineFinding(
                        fingerprint: fingerprint,
                        headline: "\(fingerprint.process) reached a new destination",
                        detail: known > 0
                            ? "\(fingerprint.process) has used \(known) other destination"
                              + "\(known == 1 ? "" : "s") over \(days) day\(days == 1 ? "" : "s"). "
                              + "\(fingerprint.endpoint):\(fingerprint.port) is new."
                            : "This is the first destination SentryBar has seen "
                              + "\(fingerprint.process) use in \(days) day\(days == 1 ? "" : "s").",
                        firstSeen: now
                    )
                )
            }
            prune(now: now)
        }

        save()
        return findings
    }

    /// Whether a fingerprint is already known, without recording it.
    func isKnown(_ connection: NetworkConnection) -> Bool {
        let fingerprint = ConnectionFingerprint(
            process: connection.processName,
            address: connection.remoteAddress,
            port: connection.remotePort
        )
        return queue.sync { entries[fingerprint] != nil }
    }

    /// What has been learned, grouped by process, most endpoints first.
    ///
    /// Settings needs this to show the user what the baseline actually holds.
    /// Without it, `reset()` and `forget(process:)` are a pair of methods with
    /// nothing to call them: the tests exercised both while no view could
    /// reach either, and the README told people to use a Settings control that
    /// did not exist.
    func learnedProcesses() -> [LearnedProcess] {
        queue.sync {
            var grouped: [String: (endpoints: Int, lastSeen: Date)] = [:]
            for (fingerprint, entry) in entries {
                let existing = grouped[fingerprint.process]
                grouped[fingerprint.process] = (
                    endpoints: (existing?.endpoints ?? 0) + 1,
                    lastSeen: max(existing?.lastSeen ?? .distantPast, entry.lastSeen)
                )
            }
            return grouped
                .map { LearnedProcess(process: $0.key, endpoints: $0.value.endpoints, lastSeen: $0.value.lastSeen) }
                .sorted {
                    $0.endpoints == $1.endpoints
                        ? $0.process.localizedCaseInsensitiveCompare($1.process) == .orderedAscending
                        : $0.endpoints > $1.endpoints
                }
        }
    }

    /// Forget everything and start learning again.
    func reset(now: Date = Date()) {
        queue.sync {
            entries.removeAll()
            startedLearning = now
        }
        save()
    }

    /// Forget one process, for when a legitimate app changes its endpoints.
    func forget(process: String) {
        queue.sync {
            entries = entries.filter { $0.key.process != process }
        }
        save()
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-retention)
        entries = entries.filter { $0.value.lastSeen >= cutoff }
        guard entries.count > maxEntries else { return }
        // Drop the least recently seen first.
        let surplus = entries.count - maxEntries
        let doomed = entries
            .sorted { $0.value.lastSeen < $1.value.lastSeen }
            .prefix(surplus)
            .map(\.key)
        for key in doomed { entries.removeValue(forKey: key) }
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var startedLearning: Date
        var entries: [StoredEntry]

        struct StoredEntry: Codable {
            let fingerprint: ConnectionFingerprint
            let entry: BaselineEntry
        }
    }

    private func load() {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url) else { return }
        guard let snapshot = try? JSONDecoder.baseline.decode(Snapshot.self, from: data) else {
            // A corrupt baseline is not worth crashing over, and is not worth
            // trusting either: start again rather than half-load it.
            return
        }
        startedLearning = snapshot.startedLearning
        entries = Dictionary(
            uniqueKeysWithValues: snapshot.entries.map { ($0.fingerprint, $0.entry) }
        )
    }

    private func save() {
        guard let url = storageURL else { return }
        let snapshot = queue.sync {
            Snapshot(
                startedLearning: startedLearning,
                entries: entries.map { Snapshot.StoredEntry(fingerprint: $0.key, entry: $0.value) }
            )
        }
        guard let data = try? JSONEncoder.baseline.encode(snapshot) else { return }
        // Write to a sibling then rename, so an interrupted save cannot leave a
        // truncated baseline behind.
        let temporary = url.appendingPathExtension("tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path
            )
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }
}

private extension JSONEncoder {
    static let baseline: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let baseline: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
