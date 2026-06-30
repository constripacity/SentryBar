import SwiftUI

/// The "Remora" menubar tab: the wire-security verdict from the Remora engine — risk dial, trust
/// banner, MITRE ATT&CK chips, and ranked findings. Styled to match NetworkMonitorView's cards.
struct VerdictView: View {
    @ObservedObject var viewModel: RemoraViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                runCard
                if let verdict = viewModel.verdict {
                    dialCard(verdict)
                    if !verdict.techniques.isEmpty { attackCard(verdict) }
                    findingsCard(verdict)
                } else {
                    emptyCard
                }
            }
            .padding(16)
        }
    }

    // MARK: - Run / reachability

    private var runCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(viewModel.isReachable ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("Remora engine").font(.caption.weight(.semibold))
                Text(viewModel.isReachable ? "reachable on 127.0.0.1" : "not reachable")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.runTriage()
            } label: {
                if viewModel.isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Run wire triage")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.isRunning)
        }
        .cardStyle()
    }

    // MARK: - Risk dial + trust

    private func dialCard(_ verdict: RemoraVerdict) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.2), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(verdict.riskScore, 0), 100)) / 100)
                        .stroke(verdict.band.color,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(verdict.riskScore)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                        Text(verdict.band.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(verdict.band.color)
                    }
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(verdict.trustColor).frame(width: 8, height: 8)
                        Text(verdict.trust.uppercased())
                            .font(.caption.weight(.bold)).foregroundStyle(verdict.trustColor)
                    }
                    Text(verdict.summary)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let focus = verdict.focus {
                        Text("▸ Look first: \(focus)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let drivers = verdict.stats.riskScore?.drivers, !drivers.isEmpty {
                HStack(spacing: 8) {
                    ForEach(drivers) { driver in
                        Text("\(driver.check) +\(driver.points)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(RemoraSeverity.color(driver.severity))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - MITRE ATT&CK

    private func attackCard(_ verdict: RemoraVerdict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MITRE ATT&CK")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(verdict.techniques) { technique in
                        Text(technique.techniqueID)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(tacticColor(technique.tactic).opacity(0.22)))
                            .overlay(Capsule().stroke(tacticColor(technique.tactic), lineWidth: 1))
                            .help("\(technique.name) · \(technique.tactic)")
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Findings

    private func findingsCard(_ verdict: RemoraVerdict) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FINDINGS")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if verdict.findings.isEmpty {
                Text("No findings — nothing unusual on the wire.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(verdict.findings) { finding in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(finding.severity.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(RemoraSeverity.color(finding.severity).opacity(0.22)))
                                .foregroundStyle(RemoraSeverity.color(finding.severity))
                            Text(finding.check)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Text(finding.title).font(.callout.weight(.medium))
                        if !finding.recommendation.isEmpty {
                            Text("▸ \(finding.recommendation)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(RemoraSeverity.color(finding.severity).opacity(0.08)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Empty state

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(viewModel.lastError
                 ?? "Run a wire triage to see the verdict, 0-100 risk score, and ATT&CK mapping.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }

    private func tacticColor(_ tactic: String) -> Color {
        switch tactic {
        case "Credential Access":   return .orange
        case "Command and Control": return .red
        case "Discovery":           return .blue
        case "Collection":          return .purple
        case "Lateral Movement":    return .yellow
        default:                    return .gray
        }
    }
}

private extension View {
    /// The card chrome NetworkMonitorView uses, factored out for the Remora cards.
    func cardStyle() -> some View {
        self
            .padding(12)
            .background(.background.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
