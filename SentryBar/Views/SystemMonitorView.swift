import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject var viewModel: SystemViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                batteryCard
                thermalCard
                topProcessesCard
            }
            .padding(16)
        }
    }

    // MARK: - Battery Card

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Battery", systemImage: "battery.100")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                // Battery health ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                        .frame(width: 50, height: 50)

                    Circle()
                        .trim(from: 0, to: CGFloat(viewModel.batteryInfo.healthPercent) / 100)
                        .stroke(
                            batteryHealthColor,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))

                    Text("\(viewModel.batteryInfo.healthPercent)%")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Health")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.batteryInfo.healthPercent)%")
                            .fontWeight(.medium)
                    }
                    .font(.caption)

                    HStack {
                        Text("Cycles")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.batteryInfo.cycleCount)")
                            .fontWeight(.medium)
                    }
                    .font(.caption)

                    HStack {
                        Text("Status")
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.batteryInfo.isCharging ? "bolt.fill" : "battery.100")
                                .font(.caption2)
                                .foregroundStyle(viewModel.batteryInfo.isCharging ? .green : .primary)
                            Text(viewModel.batteryInfo.isCharging ? "Charging" : "On Battery")
                                .fontWeight(.medium)
                        }
                    }
                    .font(.caption)

                    HStack {
                        Text("Level")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.batteryInfo.currentCharge)%")
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }
                .padding(.leading, 8)
            }
        }
        .padding(12)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    private var batteryHealthColor: Color {
        let health = viewModel.batteryInfo.healthPercent
        if health >= 80 { return .green }
        if health >= 50 { return .orange }
        return .red
    }

    // MARK: - Thermal Card

    private var thermalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Thermal State", systemImage: "thermometer.medium")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                thermalIndicator
                    .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.thermalInfo.stateDescription)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(thermalColor)

                    Text(viewModel.thermalInfo.recommendation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 8)

                Spacer()
            }
        }
        .padding(12)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    private var thermalIndicator: some View {
        ZStack {
            Circle()
                .fill(thermalColor.opacity(0.15))
            Image(systemName: thermalIcon)
                .font(.title3)
                .foregroundStyle(thermalColor)
        }
    }

    private var thermalColor: Color {
        switch viewModel.thermalInfo.state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }

    private var thermalIcon: String {
        switch viewModel.thermalInfo.state {
        case .nominal: return "checkmark.circle.fill"
        case .fair: return "exclamationmark.triangle.fill"
        case .serious: return "flame.fill"
        case .critical: return "bolt.trianglebadge.exclamationmark.fill"
        @unknown default: return "questionmark.circle.fill"
        }
    }

    // MARK: - Top Processes Card

    private var topProcessesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Top Energy Consumers", systemImage: "bolt.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if viewModel.topProcesses.isEmpty {
                Text("Scanning processes...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.topProcesses) { process in
                    HStack {
                        Text(process.name)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        Text(String(format: "%.1f%%", process.cpuUsage))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(process.cpuUsage > 50 ? .red : .secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}
