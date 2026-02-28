import SwiftUI

struct NetworkMonitorView: View {
    @ObservedObject var viewModel: NetworkViewModel
    @State private var connectionToKill: NetworkConnection?
    @State private var showKillConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryCard
                topConsumersCard
                connectionsCard
            }
            .padding(16)
        }
        .alert("Terminate Process?", isPresented: $showKillConfirmation, presenting: connectionToKill) { connection in
            Button("Cancel", role: .cancel) {}
            Button("Terminate", role: .destructive) {
                viewModel.killProcess(pid: connection.pid)
            }
        } message: { connection in
            Text("This will terminate \"\(connection.processName)\" (PID \(connection.pid)). The process may lose unsaved data.")
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Network Activity", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if viewModel.isMeasuringBandwidth {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
            }

            HStack(spacing: 16) {
                StatBadge(
                    icon: "arrow.up.circle.fill",
                    label: "Upload",
                    value: viewModel.formattedUpload,
                    color: bandwidthColor(viewModel.currentBandwidth.totalBytesOut)
                )

                StatBadge(
                    icon: "arrow.down.circle.fill",
                    label: "Download",
                    value: viewModel.formattedDownload,
                    color: bandwidthColor(viewModel.currentBandwidth.totalBytesIn)
                )

                StatBadge(
                    icon: "link.circle.fill",
                    label: "Connections",
                    value: "\(viewModel.connections.count)",
                    color: .purple
                )

                if viewModel.trustedCount > 0 {
                    StatBadge(
                        icon: "checkmark.shield.fill",
                        label: "Trusted",
                        value: "\(viewModel.trustedCount)",
                        color: .green
                    )
                }

                if viewModel.suspiciousCount > 0 {
                    StatBadge(
                        icon: "exclamationmark.triangle.fill",
                        label: "Suspicious",
                        value: "\(viewModel.suspiciousCount)",
                        color: .red
                    )
                }
            }

            // Sparkline section (appears after 2+ measurements)
            if viewModel.bandwidthHistory.count >= 2 {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        SparklineView(
                            dataPoints: viewModel.uploadRateHistory,
                            color: bandwidthColor(viewModel.currentBandwidth.totalBytesOut)
                        )
                        .frame(height: 20)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        SparklineView(
                            dataPoints: viewModel.downloadRateHistory,
                            color: bandwidthColor(viewModel.currentBandwidth.totalBytesIn)
                        )
                        .frame(height: 20)
                    }
                }
                .padding(.top, 4)
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

    private func bandwidthColor(_ bytes: UInt64) -> Color {
        let mb = Double(bytes) / (1024 * 1024)
        if mb > 10 { return .red }
        if mb > 1 { return .orange }
        return bytes > 0 ? .green : .blue
    }

    // MARK: - Top Bandwidth Consumers Card

    private var topConsumersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Top Bandwidth Consumers", systemImage: "chart.bar.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            let consumers = viewModel.currentBandwidth.topConsumers(limit: 5)

            if consumers.isEmpty {
                HStack(spacing: 6) {
                    if viewModel.isMeasuringBandwidth {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }
                    Text(viewModel.isMeasuringBandwidth ? "Measuring bandwidth..." : "No bandwidth data yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                let maxBytes = consumers.first?.totalBytes ?? 1
                ForEach(consumers) { process in
                    BandwidthConsumerRow(process: process, maxBytes: maxBytes, duration: viewModel.currentBandwidth.duration)
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

    // MARK: - Connections Card

    private var connectionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Active Connections", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh connections")
            }

            if viewModel.connections.isEmpty {
                Text("Scanning network connections...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(viewModel.sortedConnections) { connection in
                    ConnectionRow(connection: connection, bandwidthDuration: viewModel.currentBandwidth.duration, onKill: {
                        connectionToKill = connection
                        showKillConfirmation = true
                    })
                    .contextMenu {
                        connectionContextMenu(for: connection)
                    }
                    if connection.id != viewModel.sortedConnections.last?.id {
                        Divider()
                    }
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

    // MARK: - Context Menu

    @ViewBuilder
    private func connectionContextMenu(for connection: NetworkConnection) -> some View {
        Button {
            viewModel.trustProcess(connection.processName)
        } label: {
            Label("Trust \"\(connection.processName)\"", systemImage: "checkmark.shield")
        }

        Button {
            viewModel.trustAddress(connection.remoteAddress)
        } label: {
            Label("Trust \(connection.remoteAddress)", systemImage: "checkmark.shield")
        }

        Divider()

        Button {
            viewModel.blockProcess(connection.processName)
        } label: {
            Label("Block \"\(connection.processName)\"", systemImage: "xmark.shield")
        }

        Button {
            viewModel.blockAddress(connection.remoteAddress)
        } label: {
            Label("Block \(connection.remoteAddress)", systemImage: "xmark.shield")
        }

        Divider()

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(connection.remoteAddress):\(connection.remotePort)", forType: .string)
        } label: {
            Label("Copy Address", systemImage: "doc.on.doc")
        }
    }
}

// MARK: - Subviews

struct StatBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BandwidthConsumerRow: View {
    let process: ProcessBandwidth
    let maxBytes: UInt64
    let duration: TimeInterval

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(process.processName)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text("↑\(process.formattedRateOut(duration: duration))  ↓\(process.formattedRateIn(duration: duration))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let fraction = maxBytes > 0 ? CGFloat(process.totalBytes) / CGFloat(maxBytes) : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: geo.size.width * fraction)
            }
            .frame(height: 4)
        }
    }
}

struct ConnectionRow: View {
    let connection: NetworkConnection
    let bandwidthDuration: TimeInterval
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator with classification
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(connection.processName)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    if let classification = connection.userClassification {
                        Text(classification == .allowed ? "Trusted" : "Blocked")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(classification == .allowed ? .green : .red)
                    }
                }

                Text("\(connection.remoteAddress):\(connection.remotePort)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Per-connection bandwidth rate (if available)
                if let bytesIn = connection.bytesIn, let bytesOut = connection.bytesOut,
                   bytesIn > 0 || bytesOut > 0 {
                    let rateIn = bandwidthDuration > 0 ? Double(bytesIn) / bandwidthDuration : 0
                    let rateOut = bandwidthDuration > 0 ? Double(bytesOut) / bandwidthDuration : 0
                    Text("↑\(formatRate(rateOut))  ↓\(formatRate(rateIn))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(connection.protocol)
                .font(.system(size: 9, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.15))
                .clipShape(Capsule())

            // Kill button (only for non-system processes)
            if connection.canKill {
                Button {
                    onKill()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Terminate \(connection.processName)")
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIndicator: some View {
        Group {
            switch connection.userClassification {
            case .allowed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
            case .blocked:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
            case nil:
                Circle()
                    .fill(connection.isSuspicious ? Color.red : Color.green)
                    .frame(width: 6, height: 6)
            }
        }
    }
}
