import Foundation

struct BatteryInfo {
    var healthPercent: Int = 100
    var cycleCount: Int = 0
    var currentCharge: Int = 100
    var isCharging: Bool = false
    var timeRemaining: Int? = nil // minutes

    var timeRemainingFormatted: String {
        guard let minutes = timeRemaining else { return "Calculating..." }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }
}
