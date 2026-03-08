import SwiftUI

struct RulesManagementView: View {
    @ObservedObject var ruleStore: ConnectionRuleStore
    @Binding var isShowing: Bool
    @State private var showAddForm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowing = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption2)
                        Text("Settings")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Text("Connection Rules")
                    .font(.caption.weight(.semibold))

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAddForm.toggle()
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Add a new rule")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // Inline add form
                    if showAddForm {
                        AddRuleForm(ruleStore: ruleStore, isShowing: $showAddForm)
                    }

                    if ruleStore.rules.isEmpty && !showAddForm {
                        emptyState
                    } else {
                        rulesList
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                Text("\(ruleStore.allowedCount) trusted, \(ruleStore.blockedCount) blocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowing = false
                    }
                }
                .font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Rules List

    private var rulesList: some View {
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

// MARK: - Inline Add Rule Form

struct AddRuleForm: View {
    @ObservedObject var ruleStore: ConnectionRuleStore
    @Binding var isShowing: Bool
    @State private var ruleType: RuleType = .allowed
    @State private var matchField: MatchField = .processName
    @State private var matchValue = ""
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("New Rule")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowing = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel adding rule")
            }

            Picker("Type", selection: $ruleType) {
                Text("Allow").tag(RuleType.allowed)
                Text("Block").tag(RuleType.blocked)
            }
            .pickerStyle(.segmented)
            .help("Choose whether to trust or block matching connections")

            Picker("Match By", selection: $matchField) {
                ForEach(MatchField.allCases, id: \.self) { field in
                    Text(field.label).tag(field)
                }
            }
            .font(.caption)
            .help("Which connection property to match against")

            TextField(placeholder, text: $matchValue)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .help("Enter the value to match")

            TextField("Note (optional)", text: $note)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .help("Optional description for this rule")

            HStack {
                Spacer()
                Button("Add Rule") {
                    let rule = ConnectionRule(
                        ruleType: ruleType,
                        matchField: matchField,
                        matchValue: matchValue,
                        note: note.isEmpty ? nil : note
                    )
                    ruleStore.addRule(rule)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowing = false
                    }
                }
                .font(.caption.weight(.medium))
                .disabled(matchValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var placeholder: String {
        switch matchField {
        case .processName: return "e.g., Safari"
        case .remoteAddress: return "e.g., 192.168.1.100"
        case .remotePort: return "e.g., 443"
        }
    }
}
