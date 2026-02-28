import Foundation

struct ThermalInfo {
    var state: ProcessInfo.ThermalState = .nominal

    var stateDescription: String {
        switch state {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair — Slightly Warm"
        case .serious:  return "Serious — Throttling"
        case .critical: return "Critical — Heavy Throttling"
        @unknown default: return "Unknown"
        }
    }

    var recommendation: String {
        switch state {
        case .nominal:  return "System is running cool and efficient."
        case .fair:     return "Light thermal pressure. Consider closing heavy apps."
        case .serious:  return "CPU is being throttled. Close resource-heavy apps."
        case .critical: return "Severe throttling! Close apps and let the system cool."
        @unknown default: return "Unable to determine thermal state."
        }
    }
}
