import SwiftUI

struct NetworkMonitorView: View {
    @ObservedObject var viewModel: NetworkViewModel
    @State private var connectionToKill: NetworkConnection?
    @State private var showKillConfirmation = false
    @State private var expandedApps: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if viewModel.suspiciousCount > 0 {
                    suspiciousAlertBanner
                }
                summaryCard
                dataUsageCard
                topConsumersCard
                appsCard
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

    // MARK: - Suspicious Alert Banner

    private var suspiciousAlertBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title3)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.suspiciousCount) suspicious connection\(viewModel.suspiciousCount == 1 ? "" : "s") detected")
                    .font(.caption.weight(.semibold))
                Text("Review and block in the apps below")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
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
                    icon: "app.connected.to.app.below.fill",
                    label: "Active Apps",
                    value: "\(groupedConnections.count)",
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

    // MARK: - Session Data Usage Card

    private var dataUsageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Session Data Usage", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(viewModel.formattedSessionTotal)
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(.primary)
            }

            // Upload / Download totals
            HStack(spacing: 16) {
                // Upload
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Uploaded")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(viewModel.formattedSessionOut)
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Download
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Downloaded")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(viewModel.formattedSessionIn)
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Per-app usage breakdown (top 5)
            let topApps = Array(viewModel.topSessionApps.prefix(5))
            if !topApps.isEmpty {
                Divider()

                ForEach(topApps, id: \.name) { app in
                    let total = app.bytesIn + app.bytesOut
                    let maxTotal = (topApps.first.map { $0.bytesIn + $0.bytesOut }) ?? 1
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(width: 100, alignment: .leading)

                        GeometryReader { geo in
                            let fraction = maxTotal > 0 ? CGFloat(total) / CGFloat(maxTotal) : 0
                            HStack(spacing: 0) {
                                let outFraction = total > 0 ? CGFloat(app.bytesOut) / CGFloat(total) : 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.orange.opacity(0.5))
                                    .frame(width: geo.size.width * fraction * outFraction)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.cyan.opacity(0.5))
                                    .frame(width: geo.size.width * fraction * (1 - outFraction))
                            }
                        }
                        .frame(height: 4)

                        Text(formatBytes(total))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 55, alignment: .trailing)
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

    // MARK: - Apps Card (Grouped Connections)

    /// Connections grouped by process name, sorted: blocked → suspicious → normal → trusted
    private var groupedConnections: [(name: String, connections: [NetworkConnection])] {
        let grouped = Dictionary(grouping: viewModel.connections, by: \.processName)
        return grouped.map { (name: $0.key, connections: $0.value) }
            .sorted { a, b in groupSortPriority(a.connections) < groupSortPriority(b.connections) }
    }

    private func groupSortPriority(_ connections: [NetworkConnection]) -> Int {
        if connections.contains(where: { $0.userClassification == .blocked }) { return 0 }
        if connections.contains(where: { $0.isSuspicious }) { return 1 }
        if connections.contains(where: { $0.userClassification == .allowed }) { return 3 }
        return 2
    }

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Active Apps", systemImage: "square.grid.2x2")
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
                ForEach(groupedConnections, id: \.name) { group in
                    appGroupView(name: group.name, connections: group.connections)
                    if group.name != groupedConnections.last?.name {
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

    // MARK: - App Group

    private func appGroupView(name: String, connections: [NetworkConnection]) -> some View {
        let isExpanded = expandedApps.contains(name)
        let hasSuspicious = connections.contains(where: { $0.isSuspicious })
        let isBlocked = connections.contains(where: { $0.userClassification == .blocked })
        let isTrusted = connections.contains(where: { $0.userClassification == .allowed })
        let totalIn = connections.compactMap(\.bytesIn).reduce(0, +)
        let totalOut = connections.compactMap(\.bytesOut).reduce(0, +)
        let duration = viewModel.currentBandwidth.duration

        return VStack(alignment: .leading, spacing: 6) {
            // App header — tappable to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedApps.contains(name) {
                        expandedApps.remove(name)
                    } else {
                        expandedApps.insert(name)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    // Status dot
                    Circle()
                        .fill(isBlocked ? Color.red : hasSuspicious ? Color.orange : isTrusted ? Color.green : Color.blue)
                        .frame(width: 8, height: 8)

                    Text(name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text("\(connections.count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())

                    Spacer()

                    // Bandwidth summary
                    if totalIn > 0 || totalOut > 0, duration > 0 {
                        Text("↑\(formatRate(Double(totalOut) / duration))  ↓\(formatRate(Double(totalIn) / duration))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Inline action buttons
            HStack(spacing: 8) {
                if !isTrusted {
                    Button {
                        viewModel.trustProcess(name)
                    } label: {
                        Label("Trust", systemImage: "checkmark.shield")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
                    .help("Trust all connections from \(name)")
                }

                if !isBlocked {
                    Button {
                        viewModel.blockProcess(name)
                    } label: {
                        Label("Block", systemImage: "xmark.shield")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Capsule())
                    .help("Block all connections from \(name)")
                }
            }

            // Expanded connection details
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(connections) { connection in
                        connectionDetailRow(connection)
                            .contextMenu {
                                connectionContextMenu(for: connection)
                            }
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Connection Detail Row

    private func connectionDetailRow(_ connection: NetworkConnection) -> some View {
        HStack(spacing: 6) {
            Image(systemName: serviceIcon(for: connection))
                .font(.system(size: 9))
                .foregroundStyle(connection.isSuspicious ? .red : .secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(connection.serviceLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(connection.isSuspicious ? .red : .primary)

                Text(connection.remoteAddress)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Per-connection bandwidth
            if let bytesIn = connection.bytesIn, let bytesOut = connection.bytesOut,
               bytesIn > 0 || bytesOut > 0, viewModel.currentBandwidth.duration > 0 {
                let rateIn = Double(bytesIn) / viewModel.currentBandwidth.duration
                let rateOut = Double(bytesOut) / viewModel.currentBandwidth.duration
                Text("↑\(formatRate(rateOut)) ↓\(formatRate(rateIn))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            // Kill button for suspicious/blocked
            if connection.canKill, connection.isSuspicious {
                Button {
                    connectionToKill = connection
                    showKillConfirmation = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Terminate \(connection.processName)")
            }
        }
        .padding(.vertical, 2)
    }

    private func serviceIcon(for connection: NetworkConnection) -> String {
        switch connection.remotePort {
        case "443", "8443": return "lock.fill"
        case "80", "8080":  return "globe"
        case "53":          return "magnifyingglass"
        case "993", "143", "587", "465", "25": return "envelope.fill"
        case "22":          return "terminal.fill"
        case "5228", "5223": return "bell.fill"
        case "3478", "3479": return "video.fill"
        default:            return "circle.fill"
        }
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

        if connection.canKill {
            Divider()
            Button(role: .destructive) {
                connectionToKill = connection
                showKillConfirmation = true
            } label: {
                Label("Terminate Process", systemImage: "xmark.circle")
            }
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
