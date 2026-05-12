import SwiftUI

struct ReviewExtractionView: View {
    let drafts: [ExtractedDraft]
    /// draftID -> existing transaction IDs that look like duplicates
    let duplicates: [UUID: [UUID]]
    let accounts: [Account]
    var onConfirm: ([ExtractedDraft], Account) -> Void
    var onCancel: () -> Void

    @State private var editable: [ExtractedDraft]
    @State private var selected: Set<UUID>
    @State private var defaultAccountID: UUID?

    init(drafts: [ExtractedDraft],
         duplicates: [UUID: [UUID]],
         accounts: [Account],
         onConfirm: @escaping ([ExtractedDraft], Account) -> Void,
         onCancel: @escaping () -> Void) {
        self.drafts = drafts
        self.duplicates = duplicates
        self.accounts = accounts
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _editable = State(initialValue: drafts)
        // Pre-select everything EXCEPT likely duplicates.
        let nonDupes = drafts.filter { duplicates[$0.id] == nil }.map { $0.id }
        _selected = State(initialValue: Set(nonDupes))
        _defaultAccountID = State(initialValue: accounts.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    if accounts.isEmpty {
                        Text("Add a bank or cash account first (Accounts tab).")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Default account", selection: $defaultAccountID) {
                            ForEach(accounts) { a in
                                Label(a.name, systemImage: a.kind.systemImage).tag(Optional(a.id))
                            }
                        }
                    }
                } footer: {
                    if accountsHintsExist {
                        Text("Drafts the AI matched to a specific account will use that account; the rest fall back to the default above.")
                    }
                }

                Section("Found \(editable.count) transaction\(editable.count == 1 ? "" : "s")") {
                    ForEach($editable) { $d in
                        DraftRow(
                            draft: $d,
                            selected: bindingFor(d.id),
                            isDuplicate: duplicates[d.id] != nil
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)

            HStack(spacing: 12) {
                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    guard let id = defaultAccountID,
                          let acc = accounts.first(where: { $0.id == id }) else { return }
                    let chosen = editable.filter { selected.contains($0.id) }
                    onConfirm(chosen, acc)
                } label: {
                    Text("Save \(selected.count)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || defaultAccountID == nil)
            }
            .padding()
        }
    }

    private var accountsHintsExist: Bool {
        editable.contains { ($0.accountHint?.isEmpty == false) }
    }

    private func bindingFor(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn { selected.insert(id) } else { selected.remove(id) }
            }
        )
    }
}

private struct DraftRow: View {
    @Binding var draft: ExtractedDraft
    @Binding var selected: Bool
    let isDuplicate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $selected).labelsHidden()
                    .accessibilityLabel(selected ? "Include this transaction" : "Skip this transaction")
                TextField("Payee", text: $draft.payee)
                    .font(.headline)
                Spacer()
                Text(CurrencyFormatter.string(for: draft.amount, currency: draft.currency))
                    .foregroundStyle(draft.amount < 0 ? .red : .green)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                DatePicker("", selection: $draft.date, displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                if isDuplicate {
                    Label("Likely duplicate", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
                if let hint = draft.accountHint {
                    Label(hint, systemImage: "wallet.pass.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let sug = draft.suggestedCategory {
                    Label(sug, systemImage: "tag.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ConfidencePill(value: draft.confidence)
            }

            DecimalField(amount: $draft.amount, currency: draft.currency)

            if !draft.lineItems.isEmpty {
                DisclosureGroup("Line items (\(draft.lineItems.count))") {
                    ForEach(draft.lineItems) { item in
                        HStack {
                            Text(item.description).font(.caption)
                            Spacer()
                            Text(CurrencyFormatter.string(for: item.amount, currency: draft.currency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct DecimalField: View {
    @Binding var amount: Decimal
    let currency: String
    @State private var text: String = ""

    var body: some View {
        HStack {
            Text("Amount")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("0.00", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onAppear { text = (amount as NSDecimalNumber).stringValue }
                .onChange(of: text) { _, new in
                    let cleaned = new.replacingOccurrences(of: ",", with: ".")
                    if let d = Decimal(string: cleaned) { amount = d }
                }
        }
    }
}

private struct ConfidencePill: View {
    let value: Double
    var body: some View {
        let pct = Int((value * 100).rounded())
        Text("\(pct)%")
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("AI confidence \(pct) percent")
    }
    private var color: Color {
        switch value {
        case ..<0.5: return .red
        case ..<0.8: return .orange
        default:     return .green
        }
    }
}
