import Foundation

/// Shared shell execution and formatting utilities.
/// WARNING: Never interpolate user-supplied strings into the command parameter.
/// Only numeric types (Int, Int32, etc.) are safe to interpolate.
enum Shell {

    /// Executes a shell command with a timeout. Returns empty string on failure or timeout.
    static func run(_ command: String, timeout: TimeInterval = 5) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ""
        }

        // Read pipe data concurrently to avoid pipe buffer deadlock
        var outputData = Data()
        let readQueue = DispatchQueue(label: "com.sentrybar.shell.read")
        let readGroup = DispatchGroup()
        readGroup.enter()
        readQueue.async {
            outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }

        if completed.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = readGroup.wait(timeout: .now() + 1)
            return ""
        }

        _ = readGroup.wait(timeout: .now() + 1)
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

/// Shared byte formatting utility
func formatBytes(_ bytes: UInt64) -> String {
    let kb = Double(bytes) / 1024
    let mb = kb / 1024
    let gb = mb / 1024

    if gb >= 1 { return String(format: "%.1f GB", gb) }
    if mb >= 1 { return String(format: "%.1f MB", mb) }
    if kb >= 1 { return String(format: "%.0f KB", kb) }
    return "\(bytes) B"
}

/// Formats a bytes-per-second rate into a human-readable string (e.g., "1.2 KB/s")
func formatRate(_ bytesPerSecond: Double) -> String {
    let kb = bytesPerSecond / 1024
    let mb = kb / 1024
    let gb = mb / 1024

    if gb >= 1 { return String(format: "%.1f GB/s", gb) }
    if mb >= 1 { return String(format: "%.1f MB/s", mb) }
    if kb >= 1 { return String(format: "%.1f KB/s", kb) }
    return String(format: "%.0f B/s", bytesPerSecond)
}
