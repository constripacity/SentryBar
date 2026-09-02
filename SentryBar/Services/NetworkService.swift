import Darwin
import Foundation

/// Reads active network connections and process activity from macOS system tools.
///
/// This service deliberately uses `lsof` and `nettop` rather than a Network
/// Extension. That is a product decision, not a shortcut: a Network Extension
/// requires a system-extension approval that many managed Macs will never grant,
/// and it puts SentryBar in the data path of every packet. Reading the socket
/// table means SentryBar can **watch and warn but never block**, which is stated
/// plainly in the README rather than implied away.
///
/// Consequences of that choice, also stated plainly:
/// - polling misses connections that open and close between refreshes;
/// - it is slower than a kernel filter;
/// - "connection rules" can only ever alert.
final class NetworkService {

    /// Whatever the last read produced, so a view can distinguish
    /// "nothing is connected" from "the read failed".
    private(set) var lastResult: ToolResult = .success("")

    // MARK: - Connections

    /// Returns the current TCP/UDP connections.
    ///
    /// - Parameter includeListening: also report sockets in LISTEN. The previous
    ///   implementation piped through `grep ESTABLISHED`, which filtered these
    ///   out at the source while the parser still carried dead code for handling
    ///   them.
    func getConnections(includeListening: Bool = false) -> [NetworkConnection] {
        // -i   internet sockets   -n  no DNS   -P  no port-name lookup
        // -F   field output: a stable, machine-readable format that does not
        //      shift columns the way the default table does when a value is wide.
        let result = ProcessRunner.run(.lsof, ["-i", "-n", "-P", "-F", "pcnPT"], timeout: 6)
        lastResult = result
        guard result.isSuccess else { return [] }
        return parseLsofFieldOutput(result.output, includeListening: includeListening)
    }

    /// Parses `lsof -F pcnPT` output.
    ///
    /// Field output is one `<tag><value>` per line. `p` opens a process record,
    /// `f` opens a file record, and the remaining tags describe it:
    ///
    /// ```
    /// p1234
    /// cSafari
    /// f42
    /// PTCP
    /// n192.168.1.10:52344->140.82.121.4:443
    /// TST=ESTABLISHED
    /// ```
    ///
    /// The old parser split the default table on whitespace and indexed fixed
    /// column numbers, which breaks whenever a process name contains a space or
    /// a column is wide enough to shift the rest of the row.
    func parseLsofFieldOutput(_ output: String, includeListening: Bool = false) -> [NetworkConnection] {
        var connections: [NetworkConnection] = []
        var currentPID: Int32 = 0
        var currentName = ""
        var pendingProtocol = ""
        var pendingName = ""
        var pendingState = ""

        func flush() {
            defer {
                pendingProtocol = ""
                pendingName = ""
                pendingState = ""
            }
            guard !pendingName.isEmpty, !currentName.isEmpty else { return }

            let state = pendingState.isEmpty ? "UNKNOWN" : pendingState
            let isListening = state.uppercased().contains("LISTEN") || pendingName.hasSuffix("*")
            if isListening && !includeListening { return }
            if !isListening && state != "UNKNOWN" && !state.uppercased().contains("ESTABLISHED") {
                // TIME_WAIT, CLOSE_WAIT and friends are noise in a live view.
                return
            }

            let (address, port) = parseConnectionString(pendingName)
            guard !address.isEmpty else { return }

            connections.append(
                NetworkConnection(
                    processName: currentName,
                    pid: currentPID,
                    remoteAddress: address,
                    remotePort: port,
                    protocol: pendingProtocol.isEmpty ? "TCP" : pendingProtocol,
                    state: state,
                    canKill: !NetworkConnection.systemProcesses.contains(currentName),
                    heuristicSuspicious: false // filled in by the baseline, not here
                )
            )
        }

        for rawLine in output.components(separatedBy: "\n") {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())

            switch tag {
            case "p":
                flush()
                currentPID = Int32(value) ?? 0
            case "c":
                currentName = unescapeLsof(value)
            case "f":
                flush()
            case "P":
                pendingProtocol = value.uppercased()
            case "n":
                pendingName = value
            case "T":
                // TST=ESTABLISHED, TQR=0, TQS=0 — only the state matters here.
                if value.hasPrefix("ST=") {
                    pendingState = String(value.dropFirst(3))
                }
            default:
                continue
            }
        }
        flush()
        return connections
    }

    /// Splits `local->remote` or `address:port` into an address and a port.
    func parseConnectionString(_ str: String) -> (address: String, port: String) {
        var remote = str
        if let arrow = str.range(of: "->") {
            remote = String(str[arrow.upperBound...])
        } else if str.contains("->") == false && str.contains(":") == false {
            return (str, "?")
        }

        guard let lastColon = remote.lastIndex(of: ":") else {
            return (remote, "?")
        }
        var address = String(remote[remote.startIndex..<lastColon])
        let port = String(remote[remote.index(after: lastColon)...])

        if address.hasPrefix("[") && address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        return (address, port)
    }

    // MARK: - Processes

    func getTopProcesses(limit: Int = 5) -> [AppProcess] {
        // `limit` is an Int, so it cannot carry anything but digits into argv,
        // and there is no shell to interpret it in any case.
        let result = ProcessRunner.run(.ps, ["-Ao", "pid,comm,%cpu", "-r"], timeout: 4)
        guard result.isSuccess else { return [] }
        return Array(parsePsOutput(result.output).prefix(limit))
    }

    func parsePsOutput(_ output: String) -> [AppProcess] {
        output
            .components(separatedBy: "\n")
            .dropFirst() // header
            .compactMap { line -> AppProcess? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 3,
                      let pid = Int32(parts[0]),
                      let cpu = Double(parts[parts.count - 1]),
                      cpu > 0 else { return nil }

                // The command may contain spaces, so it is everything between
                // the PID and the CPU column.
                let command = parts.dropFirst().dropLast().joined(separator: " ")
                let name = String(command.split(separator: "/").last ?? Substring(command))
                return AppProcess(name: name, pid: pid, cpuUsage: cpu)
            }
    }

    // MARK: - Terminating a process

    /// Asks a process to quit.
    ///
    /// The previous version had a time-of-check/time-of-use race: it ran
    /// `ps -p <pid> -o user=` in one shell to check the owner, then `kill <pid>`
    /// in a *second* shell. Between the two the PID could be recycled by an
    /// unrelated — possibly root-owned — process, and the second command would
    /// signal whatever now held that number.
    ///
    /// This version reads the owner with `sysctl` and then calls `kill(2)`
    /// directly, and additionally requires that the caller name the process it
    /// believes it is signalling. If the name no longer matches, the PID was
    /// recycled and nothing is sent.
    func terminate(pid: Int32, expectedName: String) -> TerminateOutcome {
        guard pid > 1 else { return .refused(reason: "PID \(pid) is a system process.") }

        guard let info = processInfo(pid: pid) else {
            return .refused(reason: "That process is no longer running.")
        }
        guard info.uid == getuid() else {
            return .refused(
                reason: "\(info.name) is not owned by you. SentryBar only signals your own "
                      + "processes, and never asks for elevated privileges."
            )
        }
        guard info.name == expectedName else {
            return .refused(
                reason: "PID \(pid) is now \(info.name), not \(expectedName). "
                      + "The process ended and the number was reused; nothing was sent."
            )
        }
        guard !NetworkConnection.systemProcesses.contains(info.name) else {
            return .refused(reason: "\(info.name) is a macOS system service.")
        }

        if kill(pid, SIGTERM) == 0 {
            return .signalled
        }
        return .failed(reason: String(cString: strerror(errno)))
    }

    /// Owner and executable name for a PID, read from the kernel process table.
    ///
    /// `sysctl(KERN_PROC_PID)` answers both questions in one syscall, so there is
    /// no window between learning who owns a process and acting on it.
    func processInfo(pid: Int32) -> (name: String, uid: uid_t)? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }

        let name = withUnsafePointer(to: info.kp_proc.p_comm) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                String(cString: $0)
            }
        }
        guard !name.isEmpty else { return nil }
        return (name, info.kp_eproc.e_ucred.cr_uid)
    }

    // MARK: - Helpers

    /// Decodes `lsof`'s `\xHH` escapes for bytes it will not print raw.
    func unescapeLsof(_ input: String) -> String {
        guard input.contains("\\x") else { return input }

        var result = ""
        var index = input.startIndex
        while index < input.endIndex {
            let next = input.index(after: index)
            if input[index] == "\\", next < input.endIndex, input[next] == "x" {
                let hexStart = input.index(index, offsetBy: 2)
                if hexStart < input.endIndex {
                    let available = input.distance(from: hexStart, to: input.endIndex)
                    let hexEnd = input.index(hexStart, offsetBy: min(2, available))
                    let hex = String(input[hexStart..<hexEnd])
                    if hex.count == 2, let byte = UInt8(hex, radix: 16) {
                        result.append(Character(UnicodeScalar(byte)))
                        index = hexEnd
                        continue
                    }
                }
            }
            result.append(input[index])
            index = input.index(after: index)
        }
        return result
    }
}

/// What happened when SentryBar was asked to end a process.
enum TerminateOutcome: Equatable {
    case signalled
    case refused(reason: String)
    case failed(reason: String)

    var succeeded: Bool { self == .signalled }

    var message: String {
        switch self {
        case .signalled:            return "Asked the process to quit."
        case let .refused(reason):  return reason
        case let .failed(reason):   return "Could not signal the process: \(reason)"
        }
    }
}
