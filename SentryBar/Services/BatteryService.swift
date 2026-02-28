import Foundation
import IOKit.ps

/// Reads battery health, cycle count, and charge status via IOKit
final class BatteryService {

    /// Fetches current battery information from the system
    func getBatteryInfo() -> BatteryInfo {
        var info = BatteryInfo()

        // Get power source info
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any]
        else {
            return info
        }

        // Current charge level
        if let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int {
            info.currentCharge = currentCapacity
        }

        // Charging status
        if let isCharging = description[kIOPSIsChargingKey] as? Bool {
            info.isCharging = isCharging
        }

        // Time remaining
        if let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int, timeToEmpty > 0 {
            info.timeRemaining = timeToEmpty
        }

        // Battery health & cycle count from IORegistry
        if let batteryData = getBatteryRegistryData() {
            info.healthPercent = batteryData.healthPercent
            info.cycleCount = batteryData.cycleCount
        }

        return info
    }

    /// Reads detailed battery data from IORegistry (IOKit)
    private func getBatteryRegistryData() -> (healthPercent: Int, cycleCount: Int)? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )

        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var healthPercent = 100
        var cycleCount = 0

        // Max capacity (design vs current)
        // Apple Silicon uses "AppleRawMaxCapacity" for raw mAh; "MaxCapacity" may be a percentage.
        // Intel Macs use "MaxCapacity" for raw mAh. Try raw key first, then fall back.
        let rawMax = getIORegistryValue(service: service, key: "AppleRawMaxCapacity") as? Int
        let fallbackMax = getIORegistryValue(service: service, key: "MaxCapacity") as? Int

        if let designCapacity = getIORegistryValue(service: service, key: "DesignCapacity") as? Int,
           designCapacity > 0 {
            if let rawMax, rawMax > 0 {
                // Apple Silicon: both values are raw mAh
                healthPercent = (rawMax * 100) / designCapacity
            } else if let fallbackMax, fallbackMax > 0 {
                if fallbackMax <= 100 && designCapacity > 1000 {
                    // MaxCapacity is already a percentage (Apple Silicon without raw key)
                    healthPercent = fallbackMax
                } else {
                    // Intel: both values are raw mAh
                    healthPercent = (fallbackMax * 100) / designCapacity
                }
            }
        }

        // Cycle count
        if let cycles = getIORegistryValue(service: service, key: "CycleCount") as? Int {
            cycleCount = cycles
        }

        return (healthPercent, cycleCount)
    }

    private func getIORegistryValue(service: io_service_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
