import Foundation

/// Monitors thermal state using ProcessInfo API
final class ThermalService {
    private var thermalChangeObserver: NSObjectProtocol?

    /// Current thermal info
    func getThermalInfo() -> ThermalInfo {
        ThermalInfo(state: ProcessInfo.processInfo.thermalState)
    }

    /// Register for thermal state change notifications
    func startMonitoring(onChange: @escaping (ProcessInfo.ThermalState) -> Void) {
        thermalChangeObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            onChange(ProcessInfo.processInfo.thermalState)
        }
    }

    func stopMonitoring() {
        if let observer = thermalChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            thermalChangeObserver = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}
