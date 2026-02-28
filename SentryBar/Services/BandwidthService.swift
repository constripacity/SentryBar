import Foundation

/// Measures per-process bandwidth using macOS nettop
final class BandwidthService {

    /// Takes a one-shot bandwidth measurement via nettop.
    /// Runs nettop for 2 samples (first is "dirty" cumulative, second is actual delta).
    /// Measures actual wall-clock duration for accurate rate calculation.
    func measureBandwidth() -> BandwidthSnapshot {
        let startTime = Date()
        let output = Shell.run(
            "nettop -P -d -L 2 -J bytes_in,bytes_out -t external -c",
            timeout: 15
        )
        let duration = Date().timeIntervalSince(startTime)
        guard !output.isEmpty else { return .empty }
        return parseBandwidthOutput(output, duration: duration)
    }

    // MARK: - Parsing

    /// Parses nettop output, taking only the second sample block (actual delta).
    /// Format: process_name.PID,bytes_in,bytes_out
    /// Blocks are separated by blank lines.
    func parseBandwidthOutput(_ output: String, duration: TimeInterval = 2.0) -> BandwidthSnapshot {
        let blocks = output.components(separatedBy: "\n\n")

        // Take the second block (index 1) — it's the clean delta data
        // If only one block exists, use it (fallback)
        let targetBlock: String
        if blocks.count >= 2 {
            targetBlock = blocks[1]
        } else if let first = blocks.first {
            targetBlock = first
        } else {
            return .empty
        }

        let lines = targetBlock.components(separatedBy: "\n").filter { !$0.isEmpty }
        var aggregated: [String: (pid: Int32, bytesIn: UInt64, bytesOut: UInt64)] = [:]

        for line in lines {
            let columns = line.components(separatedBy: ",")
            guard columns.count >= 3 else { continue }

            let processField = columns[0].trimmingCharacters(in: .whitespaces)

            // Skip header lines
            guard !processField.isEmpty,
                  !processField.lowercased().contains("time") else { continue }

            // Extract process name and PID
            // Format: "process_name.PID" — split from the right since names can contain dots
            let (name, pid) = parseProcessField(processField)
            guard !name.isEmpty else { continue }

            // Parse byte values defensively
            let bytesIn = UInt64(columns[1].trimmingCharacters(in: .whitespaces)) ?? 0
            let bytesOut = UInt64(columns[2].trimmingCharacters(in: .whitespaces)) ?? 0

            // Skip zero-traffic processes
            guard bytesIn > 0 || bytesOut > 0 else { continue }

            // Aggregate by process name (multiple connections per process)
            if let existing = aggregated[name] {
                aggregated[name] = (existing.pid, existing.bytesIn + bytesIn, existing.bytesOut + bytesOut)
            } else {
                aggregated[name] = (pid, bytesIn, bytesOut)
            }
        }

        let processes = aggregated.map { name, data in
            ProcessBandwidth(
                processName: name,
                pid: data.pid,
                bytesIn: data.bytesIn,
                bytesOut: data.bytesOut
            )
        }

        return BandwidthSnapshot(timestamp: Date(), duration: duration, processes: processes)
    }

    /// Parses "process_name.PID" field, splitting from the right to handle dots in names
    func parseProcessField(_ field: String) -> (name: String, pid: Int32) {
        guard let lastDot = field.lastIndex(of: ".") else {
            return (field, 0)
        }
        let pidStr = String(field[field.index(after: lastDot)...])
        let name = String(field[field.startIndex..<lastDot])

        if let pid = Int32(pidStr) {
            return (name, pid)
        }
        // If what's after the last dot isn't a PID, treat the whole thing as the name
        return (field, 0)
    }
}
