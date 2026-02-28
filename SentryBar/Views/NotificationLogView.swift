import SwiftUI

struct NotificationLogView: View {
    @ObservedObject var notificationLog: NotificationLog

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerCard
                if notificationLog.isEmpty {
                    emptyState
                } else {
                    entriesCard
                }
            }
            .padding(16)
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Notification History", systemImage: "bell.badge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !notificationLog.isEmpty {
                    Button {
                        notificationLog.clearAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.caption2)
                            Text("Clear All")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.7))
                    .help("Clear all notification history")
                }
            }

            HStack(spacing: 16) {
                ForEach(NotificationType.allCases, id: \.self) { type in
                    let count = notificationLog.entries.filter { $0.type == type }.count
                    if count > 0 {
                        typeBadge(type: type, count: count)
                    }
                }

                if notificationLog.isEmpty {
                    Text("No alerts recorded")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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

    private func typeBadge(type: NotificationType, count: Int) -> some View {
        VStack(spacing: 4) {
            Image(systemName: type.icon)
                .font(.caption)
                .foregroundStyle(colorFor(type))
            Text("\(count)")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
            Text(type.label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No Notifications Yet")
                .font(.callout.weight(.medium))
            Text("Alerts for thermal warnings, battery health, suspicious connections, and high bandwidth will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Entries Card

    private var entriesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent Alerts", systemImage: "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(notificationLog.entries) { entry in
                entryRow(entry)
                if entry.id != notificationLog.entries.last?.id {
                    Divider()
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

    private func entryRow(_ entry: NotificationLogEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.type.icon)
                .font(.caption)
                .foregroundStyle(colorFor(entry.type))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.replacingOccurrences(of: "SentryBar: ", with: ""))
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Text(entry.body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(entry.timestamp.shortTimeString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func colorFor(_ type: NotificationType) -> Color {
        switch type {
        case .thermal:    return .orange
        case .battery:    return .yellow
        case .suspicious: return .red
        case .bandwidth:  return .purple
        }
    }
}
