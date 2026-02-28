import SwiftUI

struct RulesManagementView: View {
    @ObservedObject var ruleStore: ConnectionRuleStore
    @State private var showAddRule = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Connection Rules")
                    .font(.headline)
                Spacer()
                Button {
                    showAddRule = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Add a new rule")
            }
            .padding(16)

            Divider()

            if ruleStore.rules.isEmpty {
                emptyState
            } else {
                rulesList
            }

            Divider()

            // Footer
            HStack {
                Text("\(ruleStore.allowedCount) trusted, \(ruleStore.blockedCount) blocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .font(.caption)
            }
            .padding(16)
        }
        .frame(width: 400, height: 500)
        .sheet(isPresented: $showAddRule) {
            AddRuleView(ruleStore: ruleStore)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No Connection Rules")
                .font(.callout.weight(.medium))
            Text("Right-click any connection in the Network tab to quickly trust or block it, or tap + above to add a rule manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rules List

    private var rulesList: some View {
        ScrollView {
            VStack(spacing: 12) {
                let allowed = ruleStore.rules.filter { $0.ruleType == .allowed }
                let blocked = ruleStore.rules.filter { $0.ruleType == .blocked }

                if !allowed.isEmpty {
                    rulesSection(title: "Trusted (Allow List)", rules: allowed, color: .green)
                }

                if !blocked.isEmpty {
                    rulesSection(title: "Blocked (Block List)", rules: blocked, color: .red)
                }
            }
            .padding(16)
        }
    }

    private func rulesSection(title: String, rules: [ConnectionRule], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)

            ForEach(rules) { rule in
                ruleRow(rule)
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

    private func ruleRow(_ rule: ConnectionRule) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(rule.ruleType == .allowed ? Color.green : Color.red)
                .frame(width: 6, height: 6)

            Image(systemName: rule.matchField.icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.matchValue)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                if let note = rule.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(rule.matchField.label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)

            Button {
                ruleStore.removeRule(id: rule.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Delete this rule")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Rule Sheet

struct AddRuleView: View {
    @ObservedObject var ruleStore: ConnectionRuleStore
    @Environment(\.dismiss) private var dismiss
    @State private var ruleType: RuleType = .allowed
    @State private var matchField: MatchField = .processName
    @State private var matchValue = ""
    @State private var note = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Connection Rule")
                .font(.headline)

            Picker("Type", selection: $ruleType) {
                Text("Allow (Trusted)").tag(RuleType.allowed)
                Text("Block (Untrusted)").tag(RuleType.blocked)
            }
            .pickerStyle(.segmented)
            .help("Choose whether to trust or block matching connections")

            Picker("Match By", selection: $matchField) {
                ForEach(MatchField.allCases, id: \.self) { field in
                    Text(field.label).tag(field)
                }
            }
            .help("Which connection property to match against")

            TextField(placeholder, text: $matchValue)
                .textFieldStyle(.roundedBorder)
                .help("Enter the value to match")

            TextField("Note (optional)", text: $note)
                .textFieldStyle(.roundedBorder)
                .help("Optional description for this rule")

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add Rule") {
                    let rule = ConnectionRule(
                        ruleType: ruleType,
                        matchField: matchField,
                        matchValue: matchValue,
                        note: note.isEmpty ? nil : note
                    )
                    ruleStore.addRule(rule)
                    dismiss()
                }
                .disabled(matchValue.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var placeholder: String {
        switch matchField {
        case .processName: return "e.g., Safari"
        case .remoteAddress: return "e.g., 192.168.1.100"
        case .remotePort: return "e.g., 443"
        }
    }
}
