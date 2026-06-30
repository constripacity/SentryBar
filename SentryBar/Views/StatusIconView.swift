import SwiftUI

struct StatusIconView: View {
    @ObservedObject var systemVM: SystemViewModel
    @ObservedObject var networkVM: NetworkViewModel
    var appSettings: AppSettings
    @ObservedObject var remoraVM: RemoraViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: appSettings.menuBarIcon)
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
        }
    }

    private var statusColor: Color {
        // Red if thermal critical, suspicious connections, battery health < 50%, OR Remora rates
        // the wire high/critical risk
        if systemVM.thermalInfo.state == .critical || networkVM.suspiciousCount > 0 || systemVM.batteryInfo.healthPercent < 50
            || remoraVM.riskBand.ordinal >= RemoraBand.high.ordinal {
            return .red
        }
        // Orange if thermal warning, battery health declining, OR Remora rates the wire elevated
        if systemVM.thermalInfo.state == .serious || systemVM.thermalInfo.state == .fair || systemVM.batteryInfo.healthPercent < 80
            || remoraVM.riskBand == .elevated {
            return .orange
        }
        // Green = all good
        return .green
    }
}
