import Foundation

/// Per-process bandwidth measurement from a single nettop sample
struct ProcessBandwidth: Identifiable {
    let id = UUID()
    let processName: String
    let pid: Int32
    let bytesIn: UInt64
    let bytesOut: UInt64

    var totalBytes: UInt64 { bytesIn + bytesOut }
    var formattedIn: String { formatBytes(bytesIn) }
    var formattedOut: String { formatBytes(bytesOut) }
    var formattedTotal: String { formatBytes(totalBytes) }

    // MARK: - Rate Calculations

    func rateIn(duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return Double(bytesIn) / duration
    }

    func rateOut(duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return Double(bytesOut) / duration
    }

    func formattedRateIn(duration: TimeInterval) -> String {
        formatRate(rateIn(duration: duration))
    }

    func formattedRateOut(duration: TimeInterval) -> String {
        formatRate(rateOut(duration: duration))
    }
}

/// A point-in-time bandwidth snapshot from nettop
struct BandwidthSnapshot {
    let timestamp: Date
    let duration: TimeInterval
    let processes: [ProcessBandwidth]

    var totalBytesIn: UInt64 { processes.reduce(0) { $0 + $1.bytesIn } }
    var totalBytesOut: UInt64 { processes.reduce(0) { $0 + $1.bytesOut } }
    var formattedTotalIn: String { formatBytes(totalBytesIn) }
    var formattedTotalOut: String { formatBytes(totalBytesOut) }

    // MARK: - Rate Calculations

    var rateIn: Double {
        guard duration > 0 else { return 0 }
        return Double(totalBytesIn) / duration
    }

    var rateOut: Double {
        guard duration > 0 else { return 0 }
        return Double(totalBytesOut) / duration
    }

    var formattedRateIn: String { formatRate(rateIn) }
    var formattedRateOut: String { formatRate(rateOut) }

    /// Top bandwidth consumers sorted by total bytes descending
    func topConsumers(limit: Int = 5) -> [ProcessBandwidth] {
        Array(processes.sorted { $0.totalBytes > $1.totalBytes }.prefix(limit))
    }

    static let empty = BandwidthSnapshot(timestamp: Date(), duration: 0, processes: [])
}
