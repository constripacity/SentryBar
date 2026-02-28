import SwiftUI

struct StatusIconView: View {
    @ObservedObject var systemVM: SystemViewModel
    @ObservedObject var networkVM: NetworkViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "shield.checkered")
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
        }
    }

    private var statusColor: Color {
        // Red if thermal critical, suspicious connections, or battery health < 50%
        if systemVM.thermalInfo.state == .critical || networkVM.suspiciousCount > 0 || systemVM.batteryInfo.healthPercent < 50 {
            return .red
        }
        // Orange if thermal warning or battery health declining
        if systemVM.thermalInfo.state == .serious || systemVM.thermalInfo.state == .fair || systemVM.batteryInfo.healthPercent < 80 {
            return .orange
        }
        // Green = all good
        return .green
    }
}
