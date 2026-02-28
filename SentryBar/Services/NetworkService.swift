import Foundation

/// Monitors network connections using system tools (lsof)
final class NetworkService {

    /// Fetches active network connections by parsing `lsof` output
    func getConnections() -> [NetworkConnection] {
        let output = Shell.run("lsof -i -n -P 2>/dev/null | grep ESTABLISHED")
        return parseLsofOutput(output)
    }

    /// Gets top CPU-consuming processes via `ps`
    func getTopProcesses(limit: Int = 5) -> [AppProcess] {
        let output = Shell.run("ps -Ao pid,comm,%cpu -r | head -\(limit + 1)")
        return parsePsOutput(output)
    }

    /// Kills a process by PID. Rejects system-critical PIDs and root-owned processes.
    func killProcess(pid: Int32) -> Bool {
        guard pid > 1 else { return false }

        // Verify process is not root-owned before killing
        let owner = Shell.run("ps -p \(pid) -o user= 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, owner != "root" else { return false }

        let result = Shell.run("kill \(pid) 2>&1")
        return !result.contains("Operation not permitted")
    }

    // MARK: - Parsing

    func parseLsofOutput(_ output: String) -> [NetworkConnection] {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        return lines.compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { return nil }

            let processName = unescapeLsof(String(parts[0]))
            let pid = Int32(parts[1]) ?? 0

            // Protocol is in the NODE column (index 7): "TCP" or "UDP"
            let protocolType = String(parts[7]).uppercased().contains("TCP") ? "TCP" : "UDP"

            // Extract state from last field if it's parenthesized (e.g., "(ESTABLISHED)")
            let state: String
            if let last = parts.last, last.hasPrefix("(") && last.hasSuffix(")") {
                state = String(last.dropFirst().dropLast())
            } else {
                state = "UNKNOWN"
            }

            // Connection string: second-to-last if state is present, otherwise index 8
            let connectionStr: String
            if parts.count >= 10, parts.last?.hasPrefix("(") == true {
                connectionStr = String(parts[parts.count - 2])
            } else {
                connectionStr = String(parts[8])
            }

            let (remoteAddr, remotePort) = parseConnectionString(connectionStr)

            let isSuspicious = NetworkConnection.evaluateSuspicion(
                processName: processName,
                remotePort: remotePort,
                remoteAddress: remoteAddr
            )

            let canKill = !NetworkConnection.systemProcesses.contains(processName)

            return NetworkConnection(
                processName: processName,
                pid: pid,
                remoteAddress: remoteAddr,
                remotePort: remotePort,
                protocol: protocolType,
                state: state,
                canKill: canKill,
                heuristicSuspicious: isSuspicious
            )
        }
    }

    func parseConnectionString(_ str: String) -> (address: String, port: String) {
        // Format: "local->remote" or just "address:port"
        let remote: String
        if str.contains("->") {
            remote = String(str.components(separatedBy: "->").last ?? "")
        } else {
            remote = str
        }

        // Split address:port — use lastIndex(of: ":") to handle IPv6 colons
        if let lastColon = remote.lastIndex(of: ":") {
            var address = String(remote[remote.startIndex..<lastColon])
            let port = String(remote[remote.index(after: lastColon)...])

            // Strip IPv6 brackets: [2a02:...] → 2a02:...
            if address.hasPrefix("[") && address.hasSuffix("]") {
                address = String(address.dropFirst().dropLast())
            }

            return (address, port)
        }

        return (remote, "?")
    }

    func parsePsOutput(_ output: String) -> [AppProcess] {
        let lines = output.components(separatedBy: "\n").dropFirst() // Skip header
        return lines.compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3 else { return nil }

            let pid = Int32(parts[0]) ?? 0
            // Process name is everything between PID and CPU% — join middle parts
            let cpuStr = String(parts.last ?? "0")
            let name = parts.dropFirst().dropLast().joined(separator: " ")
            let cpu = Double(cpuStr) ?? 0

            guard cpu > 0 else { return nil }

            return AppProcess(
                name: String(name.split(separator: "/").last ?? Substring(name)),
                pid: pid,
                cpuUsage: cpu
            )
        }
    }

    // MARK: - Helpers

    /// Unescapes lsof hex escape sequences (\xHH → character)
    func unescapeLsof(_ input: String) -> String {
        guard input.contains("\\x") else { return input }

        var result = ""
        var i = input.startIndex
        while i < input.endIndex {
            if input[i] == "\\" && input.index(after: i) < input.endIndex && input[input.index(after: i)] == "x" {
                let hexStart = input.index(i, offsetBy: 2)
                if hexStart < input.endIndex {
                    let hexEnd = input.index(hexStart, offsetBy: min(2, input.distance(from: hexStart, to: input.endIndex)))
                    let hexStr = String(input[hexStart..<hexEnd])
                    if hexStr.count == 2, let byte = UInt8(hexStr, radix: 16) {
                        result.append(Character(UnicodeScalar(byte)))
                        i = hexEnd
                        continue
                    }
                }
            }
            result.append(input[i])
            i = input.index(after: i)
        }
        return result
    }

}
