import Foundation

/// Available SF Symbol options for the menubar icon
struct MenuBarIconOption {
    let symbol: String
    let label: String

    static let allOptions: [MenuBarIconOption] = [
        MenuBarIconOption(symbol: "shield.checkered", label: "Shield"),
        MenuBarIconOption(symbol: "shield.lefthalf.filled", label: "Half Shield"),
        MenuBarIconOption(symbol: "lock.shield", label: "Lock Shield"),
        MenuBarIconOption(symbol: "eye", label: "Eye"),
        MenuBarIconOption(symbol: "network", label: "Network"),
        MenuBarIconOption(symbol: "antenna.radiowaves.left.and.right", label: "Antenna"),
        MenuBarIconOption(symbol: "bolt.shield", label: "Bolt Shield"),
        MenuBarIconOption(symbol: "checkmark.shield", label: "Checkmark"),
        MenuBarIconOption(symbol: "exclamationmark.shield", label: "Alert Shield"),
        MenuBarIconOption(symbol: "cpu", label: "CPU"),
    ]
}
