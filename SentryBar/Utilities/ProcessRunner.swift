import Foundation

/// Runs a system tool and returns its output.
///
/// This replaces the previous `Shell.run(_ command: String)`, which spawned
/// `/bin/zsh -c "<string>"` for every reading. Three problems came with that:
///
/// 1. **A shell in the loop.** Every refresh started an extra process purely to
///    parse a string SentryBar had just built. The shell also brought its own
///    startup files, PATH resolution and quoting rules into a hot path.
/// 2. **An injection surface that only a comment defended.** The old file
///    carried "WARNING: Never interpolate user-supplied strings into the command
///    parameter." A comment is not a boundary. Here the executable and its
///    arguments are separate values and there is no shell to interpret them, so
///    interpolating a hostile process name cannot become a command.
/// 3. **Leaked processes and file descriptors.** On timeout the old code called
///    `terminate()` and returned without ever reaping the child or closing the
///    pipe, so a slow `lsof` left a zombie and a descriptor behind on every
///    refresh.
///
/// Tools are addressed by absolute path. `/usr/bin` and `/usr/sbin` are
/// SIP-protected on macOS, so this also removes any dependence on `PATH`.
enum SystemTool: String {
    case lsof   = "/usr/sbin/lsof"
    case nettop = "/usr/bin/nettop"
    case ps     = "/bin/ps"
    case ioreg  = "/usr/sbin/ioreg"
    case pmset  = "/usr/bin/pmset"
    case sysctl = "/usr/sbin/sysctl"

    var path: String { rawValue }

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: rawValue)
    }
}

/// The outcome of running a tool. Failures are values, not empty strings, so a
/// view can tell "nothing is connected" apart from "the reading failed".
enum ToolResult: Equatable {
    case success(String)
    case timedOut(after: TimeInterval)
    case failed(status: Int32, stderr: String)
    case unavailable(tool: String)

    var output: String {
        if case let .success(text) = self { return text }
        return ""
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// A sentence suitable for showing in the UI instead of an empty list.
    var userFacingMessage: String? {
        switch self {
        case .success:
            return nil
        case let .timedOut(after):
            return "The system took longer than \(Int(after))s to answer. "
                 + "This usually clears on the next refresh."
        case let .failed(status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "The system tool exited with status \(status)."
                : "The system tool failed: \(detail.prefix(160))"
        case let .unavailable(tool):
            return "\(tool) is not present on this Mac, so this reading is unavailable."
        }
    }
}

enum ProcessRunner {

    /// Runs `tool` with `arguments` and returns its standard output.
    ///
    /// - Note: There is no shell. `arguments` are passed to `execve` as a vector,
    ///   so no character in them is special.
    static func run(
        _ tool: SystemTool,
        _ arguments: [String],
        timeout: TimeInterval = 5,
        maxOutputBytes: Int = 4 * 1024 * 1024
    ) -> ToolResult {
        guard tool.isAvailable else {
            return .unavailable(tool: tool.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.path)
        process.arguments = arguments
        // A predictable, minimal environment: nothing here should depend on the
        // user's shell configuration.
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .failed(status: -1, stderr: error.localizedDescription)
        }

        // Both pipes are drained concurrently. Reading one to completion before
        // the other deadlocks as soon as a tool fills the 64 KB buffer of the
        // pipe nobody is reading.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.sentrybar.tool.read", attributes: .concurrent)

        group.enter()
        queue.async {
            outData = readBounded(outPipe.fileHandleForReading, limit: maxOutputBytes)
            group.leave()
        }
        group.enter()
        queue.async {
            errData = readBounded(errPipe.fileHandleForReading, limit: 64 * 1024)
            group.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            timedOut = true
            process.terminate()
            // Give it a moment to exit on SIGTERM, then insist. Without this the
            // child is never reaped and accumulates as a zombie.
            let hardDeadline = Date().addingTimeInterval(1.0)
            while process.isRunning && Date() < hardDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        _ = group.wait(timeout: .now() + 2)
        process.waitUntilExit()
        try? outPipe.fileHandleForReading.close()
        try? errPipe.fileHandleForReading.close()

        if timedOut {
            return .timedOut(after: timeout)
        }
        let status = process.terminationStatus
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        // `lsof` exits non-zero when a filter matches nothing, and `grep`-style
        // "no results" is not a failure for our purposes.
        if status != 0 && stdout.isEmpty {
            return .failed(status: status, stderr: stderr)
        }
        return .success(stdout)
    }

    /// Reads a handle to EOF, stopping at `limit` bytes.
    ///
    /// `readDataToEndOfFile()` is unbounded: a tool that produces gigabytes
    /// would be buffered entirely in memory before anyone could object.
    private static func readBounded(_ handle: FileHandle, limit: Int) -> Data {
        var collected = Data()
        while collected.count < limit {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            collected.append(chunk)
        }
        if collected.count > limit {
            collected = collected.prefix(limit)
        }
        return collected
    }
}

// MARK: - Formatting helpers (unchanged behaviour, kept here for one import)

/// Formats a byte count for display.
func formatBytes(_ bytes: UInt64) -> String {
    let kb = Double(bytes) / 1024
    let mb = kb / 1024
    let gb = mb / 1024

    if gb >= 1 { return String(format: "%.1f GB", gb) }
    if mb >= 1 { return String(format: "%.1f MB", mb) }
    if kb >= 1 { return String(format: "%.0f KB", kb) }
    return "\(bytes) B"
}

/// Formats a bytes-per-second rate for display.
func formatRate(_ bytesPerSecond: Double) -> String {
    let kb = bytesPerSecond / 1024
    let mb = kb / 1024
    let gb = mb / 1024

    if gb >= 1 { return String(format: "%.1f GB/s", gb) }
    if mb >= 1 { return String(format: "%.1f MB/s", mb) }
    if kb >= 1 { return String(format: "%.1f KB/s", kb) }
    return String(format: "%.0f B/s", bytesPerSecond)
}
